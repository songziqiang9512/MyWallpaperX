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

typedef enum MWXSceneQuickJSLayerMutationKind {
    MWX_SCENE_QUICKJS_LAYER_MUTATION_UPSERT = 1,
    MWX_SCENE_QUICKJS_LAYER_MUTATION_DESTROY = 2
} MWXSceneQuickJSLayerMutationKind;

typedef struct MWXSceneQuickJSLayerMutation {
    uint32_t kind;
    uint32_t dynamic;
    int64_t layer_id;
    int32_t order_index;
    uint32_t visible;
    double alpha;
    double origin[3];
    double scale[3];
    double angles[3];
    double color[3];
    double point_size;
    const char *text;
    const char *font;
} MWXSceneQuickJSLayerMutation;

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

typedef struct MWXSceneQuickJSMediaPropertiesEvent {
    const char *title;
    size_t title_length;
    const char *artist;
    size_t artist_length;
} MWXSceneQuickJSMediaPropertiesEvent;

typedef enum MWXSceneQuickJSCursorEventKind {
    MWX_SCENE_QUICKJS_CURSOR_ENTER = 1,
    MWX_SCENE_QUICKJS_CURSOR_LEAVE = 2,
    MWX_SCENE_QUICKJS_CURSOR_DOWN = 3,
    MWX_SCENE_QUICKJS_CURSOR_UP = 4,
    MWX_SCENE_QUICKJS_CURSOR_CLICK = 5
} MWXSceneQuickJSCursorEventKind;

typedef struct MWXSceneQuickJSCursorEvent {
    double world_x;
    double world_y;
    double world_z;
    double local_x;
    double local_y;
    double local_z;
} MWXSceneQuickJSCursorEvent;

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

MWXSceneQuickJSResult mwx_scene_quickjs_domain_set_layer_runtime_descriptor(
    MWXSceneQuickJSDomain *domain,
    uint32_t layer_index,
    int64_t layer_id,
    const char *name,
    size_t name_length,
    const double origin[3],
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
);

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
);

size_t mwx_scene_quickjs_owner_layer_mutation_count(
    const MWXSceneQuickJSOwner *owner
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_layer_mutation_at(
    MWXSceneQuickJSOwner *owner,
    size_t index,
    MWXSceneQuickJSLayerMutation *mutation,
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

MWXSceneQuickJSResult mwx_scene_quickjs_owner_configure_layer_identity(
    MWXSceneQuickJSOwner *owner,
    int64_t layer_id,
    char *diagnostic,
    size_t diagnostic_capacity
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_has_function(
    MWXSceneQuickJSOwner *owner,
    const char *name,
    size_t name_length,
    uint32_t *available,
    char *diagnostic,
    size_t diagnostic_capacity
);

size_t mwx_scene_quickjs_owner_audio_registration_count(
    const MWXSceneQuickJSOwner *owner
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_refresh_audio_resolution(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    uint32_t resolution,
    const float *left,
    const float *right,
    size_t count,
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

uint32_t mwx_scene_quickjs_owner_active_timer_count(
    MWXSceneQuickJSOwner *owner
);

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

MWXSceneQuickJSResult mwx_scene_quickjs_owner_update_scalar_with_properties(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    double input,
    const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json,
    size_t script_properties_length,
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

MWXSceneQuickJSResult mwx_scene_quickjs_owner_update_string(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    const char *input,
    size_t input_length,
    const MWXSceneQuickJSFrameInput *frame,
    const char *user_properties_json,
    size_t user_properties_length,
    char *output,
    size_t output_capacity,
    size_t *output_length,
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

MWXSceneQuickJSResult mwx_scene_quickjs_owner_dispatch_media_properties(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    const MWXSceneQuickJSMediaPropertiesEvent *event,
    const MWXSceneQuickJSFrameInput *frame,
    const char *user_properties_json,
    size_t user_properties_length,
    char *diagnostic,
    size_t diagnostic_capacity
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_dispatch_user_properties(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    const char *changed_properties_json,
    size_t changed_properties_length,
    const char *script_properties_json,
    size_t script_properties_length,
    const MWXSceneQuickJSFrameInput *frame,
    const char *user_properties_json,
    size_t user_properties_length,
    char *diagnostic,
    size_t diagnostic_capacity
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_dispatch_cursor(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    MWXSceneQuickJSCursorEventKind kind,
    const MWXSceneQuickJSCursorEvent *event,
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
