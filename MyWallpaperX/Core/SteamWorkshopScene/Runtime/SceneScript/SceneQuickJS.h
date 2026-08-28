#ifndef MWX_SCENE_QUICKJS_H
#define MWX_SCENE_QUICKJS_H

#include <stddef.h>
#include <stdint.h>

typedef struct MWXSceneQuickJSDomain MWXSceneQuickJSDomain;
typedef struct MWXSceneQuickJSOwner MWXSceneQuickJSOwner;

typedef enum MWXSceneQuickJSResult {
    MWX_SCENE_QUICKJS_OK = 0,
    MWX_SCENE_QUICKJS_INVALID_ARGUMENT = 1,
    MWX_SCENE_QUICKJS_COMPILE_ERROR = 2,
    MWX_SCENE_QUICKJS_EXCEPTION = 3,
    MWX_SCENE_QUICKJS_BUDGET_EXCEEDED = 4,
    MWX_SCENE_QUICKJS_MEMORY_EXCEEDED = 5,
    MWX_SCENE_QUICKJS_BAD_RETURN = 6,
    MWX_SCENE_QUICKJS_DISABLED = 7,
    MWX_SCENE_QUICKJS_STALE_OWNER = 8,
    MWX_SCENE_QUICKJS_MUTATION_OVERFLOW = 9
} MWXSceneQuickJSResult;

typedef struct MWXSceneQuickJSMaterialFunctionMutation {
    uint32_t effect_index;
    const char *function_name;
} MWXSceneQuickJSMaterialFunctionMutation;

typedef enum MWXSceneQuickJSAnimationCommand {
    MWX_SCENE_QUICKJS_ANIMATION_PLAY = 1,
    MWX_SCENE_QUICKJS_ANIMATION_PAUSE = 2,
    MWX_SCENE_QUICKJS_ANIMATION_STOP = 3
} MWXSceneQuickJSAnimationCommand;

typedef struct MWXSceneQuickJSFrameInput {
    double time_of_day;
    double frame_time;
    double runtime;
} MWXSceneQuickJSFrameInput;

typedef struct MWXSceneQuickJSMediaThumbnailEvent {
    uint32_t has_thumbnail;
} MWXSceneQuickJSMediaThumbnailEvent;

typedef struct MWXSceneQuickJSMediaPlaybackEvent {
    uint32_t state;
} MWXSceneQuickJSMediaPlaybackEvent;

MWXSceneQuickJSDomain *mwx_scene_quickjs_domain_create(
    size_t heap_limit,
    size_t stack_limit,
    uint64_t interrupt_budget,
    char *diagnostic,
    size_t diagnostic_capacity
);

void mwx_scene_quickjs_domain_destroy(MWXSceneQuickJSDomain *domain);

void mwx_scene_quickjs_domain_reset_budget(
    MWXSceneQuickJSDomain *domain,
    uint64_t interrupt_budget
);

MWXSceneQuickJSResult mwx_scene_quickjs_domain_configure_layer_catalog(
    MWXSceneQuickJSDomain *domain,
    uint32_t layer_count,
    char *diagnostic,
    size_t diagnostic_capacity
);

MWXSceneQuickJSResult mwx_scene_quickjs_domain_set_layer_descriptor(
    MWXSceneQuickJSDomain *domain,
    uint32_t layer_index,
    int64_t layer_id,
    const char *name,
    size_t name_length,
    const double origin[3],
    char *diagnostic,
    size_t diagnostic_capacity
);

MWXSceneQuickJSResult mwx_scene_quickjs_domain_begin_layer_snapshot(
    MWXSceneQuickJSDomain *domain,
    uint64_t generation,
    char *diagnostic,
    size_t diagnostic_capacity
);

MWXSceneQuickJSResult mwx_scene_quickjs_domain_set_layer_origin(
    MWXSceneQuickJSDomain *domain,
    uint32_t layer_index,
    const double origin[3],
    char *diagnostic,
    size_t diagnostic_capacity
);

MWXSceneQuickJSOwner *mwx_scene_quickjs_owner_create(
    MWXSceneQuickJSDomain *domain,
    const char *source,
    size_t source_length,
    uint64_t generation,
    char *diagnostic,
    size_t diagnostic_capacity
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_configure_effect_catalog(
    MWXSceneQuickJSOwner *owner,
    uint32_t effect_count,
    char *diagnostic,
    size_t diagnostic_capacity
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_set_effect_name(
    MWXSceneQuickJSOwner *owner,
    uint32_t effect_index,
    const char *name,
    size_t name_length,
    char *diagnostic,
    size_t diagnostic_capacity
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_configure_current_animation(
    MWXSceneQuickJSOwner *owner,
    uint32_t available,
    char *diagnostic,
    size_t diagnostic_capacity
);

void mwx_scene_quickjs_owner_destroy(MWXSceneQuickJSOwner *owner);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_update_scalar(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    double input,
    const MWXSceneQuickJSFrameInput *frame,
    double *output,
    char *diagnostic,
    size_t diagnostic_capacity
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_update_scalar_with_user_properties(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    double input,
    const MWXSceneQuickJSFrameInput *frame,
    const char *user_properties_json,
    size_t user_properties_length,
    double *output,
    char *diagnostic,
    size_t diagnostic_capacity
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_update_vec3(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    const double input[3],
    const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json,
    size_t script_properties_length,
    const char *user_properties_json,
    size_t user_properties_length,
    double output[3],
    char *diagnostic,
    size_t diagnostic_capacity
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_dispatch_media_thumbnail(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    const MWXSceneQuickJSMediaThumbnailEvent *event,
    const MWXSceneQuickJSFrameInput *frame,
    const char *user_properties_json,
    size_t user_properties_length,
    char *diagnostic,
    size_t diagnostic_capacity
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_dispatch_media_playback(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    const MWXSceneQuickJSMediaPlaybackEvent *event,
    const MWXSceneQuickJSFrameInput *frame,
    const char *user_properties_json,
    size_t user_properties_length,
    char *diagnostic,
    size_t diagnostic_capacity
);

size_t mwx_scene_quickjs_owner_material_function_count(
    const MWXSceneQuickJSOwner *owner
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_material_function_at(
    const MWXSceneQuickJSOwner *owner,
    size_t index,
    uint32_t *effect_index,
    char *function_name,
    size_t function_name_capacity,
    char *diagnostic,
    size_t diagnostic_capacity
);

size_t mwx_scene_quickjs_owner_animation_command_count(
    const MWXSceneQuickJSOwner *owner
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_animation_command_at(
    const MWXSceneQuickJSOwner *owner,
    size_t index,
    MWXSceneQuickJSAnimationCommand *command,
    char *diagnostic,
    size_t diagnostic_capacity
);

void mwx_scene_quickjs_owner_invalidate(MWXSceneQuickJSOwner *owner);

#endif
