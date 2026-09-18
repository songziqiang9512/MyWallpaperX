#ifndef MWX_SCENE_QUICKJS_H
#define MWX_SCENE_QUICKJS_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

typedef struct MWXSceneQuickJSDomain MWXSceneQuickJSDomain;
typedef struct MWXSceneQuickJSOwner MWXSceneQuickJSOwner;
typedef struct MWXSceneQuickJSTimerFrameSnapshot
    MWXSceneQuickJSTimerFrameSnapshot;
typedef int (*MWXSceneQuickJSCancellationCheck)(void *opaque);
typedef enum MWXSceneQuickJSStorageReadResult {
    MWX_SCENE_QUICKJS_STORAGE_READ_ERROR = -1,
    MWX_SCENE_QUICKJS_STORAGE_READ_MISSING = 0,
    MWX_SCENE_QUICKJS_STORAGE_READ_FOUND = 1,
    MWX_SCENE_QUICKJS_STORAGE_READ_BUFFER_TOO_SMALL = 2
} MWXSceneQuickJSStorageReadResult;
// All input pointers are borrowed for the duration of this call. The callback
// must copy any bytes it retains and must report the required JSON byte count.
typedef MWXSceneQuickJSStorageReadResult (*MWXSceneQuickJSStorageRead)(
    void *opaque,
    const char *screen_identity,
    size_t screen_identity_length,
    uint32_t global_scope,
    const char *key,
    size_t key_length,
    char *json,
    size_t json_capacity,
    size_t *json_length
);

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

typedef enum MWXSceneQuickJSStorageMutationKind {
    MWX_SCENE_QUICKJS_STORAGE_SET = 1,
    MWX_SCENE_QUICKJS_STORAGE_DELETE = 2,
    MWX_SCENE_QUICKJS_STORAGE_CLEAR = 3
} MWXSceneQuickJSStorageMutationKind;

typedef struct MWXSceneQuickJSStorageMutation {
    uint32_t kind;
    uint32_t global_scope;
    const char *screen_identity;
    size_t screen_identity_length;
    const char *key;
    size_t key_length;
    const char *json;
    size_t json_length;
} MWXSceneQuickJSStorageMutation;
// Pointers returned in this DTO remain borrowed from the owner until its
// storage transaction is discarded or the owner is destroyed.

typedef enum MWXSceneQuickJSLayerMutationKind {
    MWX_SCENE_QUICKJS_LAYER_MUTATION_UPSERT = 1,
    MWX_SCENE_QUICKJS_LAYER_MUTATION_DESTROY = 2
} MWXSceneQuickJSLayerMutationKind;

typedef enum MWXSceneQuickJSLayerMutationField {
    MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ORIGIN = 1u << 0,
    MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_SCALE = 1u << 1,
    MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ANGLES = 1u << 2,
    MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_VISIBILITY = 1u << 3,
    MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_TEXT = 1u << 4,
    MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_FONT = 1u << 5,
    MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ALPHA = 1u << 6,
    MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_COLOR = 1u << 7,
} MWXSceneQuickJSLayerMutationField;

typedef struct MWXSceneQuickJSLayerMutation {
    uint32_t kind;
    uint32_t dynamic;
    uint32_t fields;
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
    const char *asset_path;
} MWXSceneQuickJSLayerMutation;

/// A typed Puppet bone write emitted by the existing layer owner transaction.
/// Matrices use the public Mat4 column-major `m` order and remain borrowed
/// from the owner until the next transaction boundary.
typedef struct MWXSceneQuickJSPuppetBoneMutation {
    int64_t layer_id;
    int32_t bone_index; /* dense zero-based index */
    uint32_t local_space;
    double matrix[16];
} MWXSceneQuickJSPuppetBoneMutation;
// text/font/asset_path are borrowed from the owner/domain. Callers must copy
// them before the next layer-mutation begin/discard, snapshot replacement, or
// owner/domain destruction.

typedef enum MWXSceneQuickJSAnimationCommand {
    MWX_SCENE_QUICKJS_ANIMATION_PLAY = 1,
    MWX_SCENE_QUICKJS_ANIMATION_PAUSE = 2,
    MWX_SCENE_QUICKJS_ANIMATION_STOP = 3
} MWXSceneQuickJSAnimationCommand;

typedef enum MWXSceneQuickJSVideoCommandKind {
    MWX_SCENE_QUICKJS_VIDEO_PLAY = 1,
    MWX_SCENE_QUICKJS_VIDEO_PAUSE = 2,
    MWX_SCENE_QUICKJS_VIDEO_STOP = 3,
    MWX_SCENE_QUICKJS_VIDEO_SET_CURRENT_TIME = 4,
    MWX_SCENE_QUICKJS_VIDEO_SET_RATE = 5,
    MWX_SCENE_QUICKJS_VIDEO_SET_LOOP = 6
} MWXSceneQuickJSVideoCommandKind;

typedef struct MWXSceneQuickJSVideoCommand {
    uint32_t kind;
    int64_t layer_id;
    double number_value;
    uint32_t bool_value;
} MWXSceneQuickJSVideoCommand;

typedef enum MWXSceneQuickJSTextureAnimationCommandKind {
    MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_PLAY = 1,
    MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_PAUSE = 2,
    MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_STOP = 3,
    MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_SET_FRAME = 4,
    MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_SET_RATE = 5,
    MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_JOIN = 6
} MWXSceneQuickJSTextureAnimationCommandKind;

typedef struct MWXSceneQuickJSTextureAnimationCommand {
    uint32_t kind;
    int64_t layer_id;
    double number_value;
} MWXSceneQuickJSTextureAnimationCommand;

typedef struct MWXSceneQuickJSFrameInput {
    double time_of_day;
    double frame_time;
    double runtime;
    uint32_t has_surface_input;
    double canvas_width;
    double canvas_height;
    double screen_width;
    double screen_height;
    double cursor_world_x;
    double cursor_world_y;
    double cursor_world_z;
    double cursor_screen_x;
    double cursor_screen_y;
    uint32_t cursor_left_down;
} MWXSceneQuickJSFrameInput;

typedef struct MWXSceneQuickJSLifecycleSnapshot {
    uint32_t teardown_started;
    uint32_t destroy_callback_count;
    uint32_t active_timer_count;
    uint32_t pending_layer_mutation_count;
    uint32_t active_dynamic_layer_count;
    uint32_t has_job_residue;
    uint32_t callback_active;
} MWXSceneQuickJSLifecycleSnapshot;

typedef struct MWXSceneQuickJSMediaThumbnailEvent {
    uint32_t has_thumbnail;
    double primary_red;
    double primary_green;
    double primary_blue;
    double secondary_red;
    double secondary_green;
    double secondary_blue;
    double tertiary_red;
    double tertiary_green;
    double tertiary_blue;
    double text_red;
    double text_green;
    double text_blue;
    double high_contrast_red;
    double high_contrast_green;
    double high_contrast_blue;
} MWXSceneQuickJSMediaThumbnailEvent;

typedef struct MWXSceneQuickJSMediaPlaybackEvent {
    uint32_t state;
} MWXSceneQuickJSMediaPlaybackEvent;

typedef struct MWXSceneQuickJSMediaTimelineEvent {
    double position;
    double duration;
} MWXSceneQuickJSMediaTimelineEvent;

typedef struct MWXSceneQuickJSMediaPropertiesEvent {
    const char *title;
    size_t title_length;
    const char *artist;
    size_t artist_length;
    const char *sub_title;
    size_t sub_title_length;
    const char *album_title;
    size_t album_title_length;
    const char *album_artist;
    size_t album_artist_length;
    const char *genres;
    size_t genres_length;
    const char *content_type;
    size_t content_type_length;
} MWXSceneQuickJSMediaPropertiesEvent;

typedef enum MWXSceneQuickJSCursorEventKind {
    MWX_SCENE_QUICKJS_CURSOR_ENTER = 1,
    MWX_SCENE_QUICKJS_CURSOR_LEAVE = 2,
    MWX_SCENE_QUICKJS_CURSOR_DOWN = 3,
    MWX_SCENE_QUICKJS_CURSOR_UP = 4,
    MWX_SCENE_QUICKJS_CURSOR_CLICK = 5,
    MWX_SCENE_QUICKJS_CURSOR_MOVE = 6
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

MWXSceneQuickJSResult mwx_scene_quickjs_domain_configure_storage(
    MWXSceneQuickJSDomain *domain,
    MWXSceneQuickJSStorageRead read_callback,
    void *opaque,
    char *diagnostic,
    size_t diagnostic_capacity
);

MWXSceneQuickJSResult mwx_scene_quickjs_domain_set_storage_screen_identity(
    MWXSceneQuickJSDomain *domain,
    const char *identity,
    size_t identity_length,
    char *diagnostic,
    size_t diagnostic_capacity
);

void mwx_scene_quickjs_domain_destroy(MWXSceneQuickJSDomain *domain);

/* Exclusive handoff only: the previous thread must no longer use the domain. */
void mwx_scene_quickjs_domain_adopt_current_thread(MWXSceneQuickJSDomain *domain);

void mwx_scene_quickjs_domain_set_cancellation_check(
    MWXSceneQuickJSDomain *domain,
    MWXSceneQuickJSCancellationCheck cancellation_check,
    void *opaque
);

void mwx_scene_quickjs_domain_reset_budget(
    MWXSceneQuickJSDomain *domain,
    uint64_t interrupt_budget
);

MWXSceneQuickJSResult mwx_scene_quickjs_domain_begin_shared_frame_transaction(
    MWXSceneQuickJSDomain *domain,
    char *diagnostic,
    size_t diagnostic_capacity
);

void mwx_scene_quickjs_domain_commit_shared_frame_transaction(
    MWXSceneQuickJSDomain *domain
);

MWXSceneQuickJSResult mwx_scene_quickjs_domain_discard_shared_frame_transaction(
    MWXSceneQuickJSDomain *domain,
    char *diagnostic,
    size_t diagnostic_capacity
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
    uint32_t has_parent,
    int64_t parent_id,
    const char *name,
    size_t name_length,
    const double origin[3],
    const double size[2],
    char *diagnostic,
    size_t diagnostic_capacity
);

MWXSceneQuickJSResult mwx_scene_quickjs_domain_set_layer_runtime_descriptor(
    MWXSceneQuickJSDomain *domain,
    uint32_t layer_index,
    int64_t layer_id,
    uint32_t has_parent,
    int64_t parent_id,
    const char *name,
    size_t name_length,
    const double origin[3],
    const double size[2],
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

MWXSceneQuickJSResult mwx_scene_quickjs_domain_set_layer_mutation_capabilities(
    MWXSceneQuickJSDomain *domain,
    uint32_t layer_index,
    uint32_t text_mutable,
    char *diagnostic,
    size_t diagnostic_capacity
);

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
);

/// Marks one layer's previously committed runtime fields as unchanged for the
/// current snapshot transaction.  The transaction still requires an explicit
/// mark for every configured layer, but callers do not need to rebuild the
/// typed Swift/C payload for layers with no dynamic owner.
MWXSceneQuickJSResult mwx_scene_quickjs_domain_reuse_layer_runtime_fields(
    MWXSceneQuickJSDomain *domain,
    uint32_t layer_index,
    char *diagnostic,
    size_t diagnostic_capacity
);

/// Publishes one renderer-resolved, column-major world matrix into the current
/// immutable layer snapshot. Coordinate math remains owned by the Swift
/// world-frame resolvers; the VM bridge only validates and copies the ABI.
MWXSceneQuickJSResult mwx_scene_quickjs_domain_update_layer_world_transform(
    MWXSceneQuickJSDomain *domain,
    uint32_t layer_index,
    const double world_transform[16],
    char *diagnostic,
    size_t diagnostic_capacity
);

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
);

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
);

size_t mwx_scene_quickjs_owner_layer_mutation_count(
    const MWXSceneQuickJSOwner *owner
);
size_t mwx_scene_quickjs_owner_puppet_bone_mutation_count(
    MWXSceneQuickJSOwner *owner
);
MWXSceneQuickJSResult mwx_scene_quickjs_owner_configure_puppet_bones(
    MWXSceneQuickJSOwner *owner,
    int64_t layer_id,
    uint32_t bone_count,
    const double *world_matrices,
    const double *local_matrices,
    char *diagnostic,
    size_t diagnostic_capacity
);
MWXSceneQuickJSResult mwx_scene_quickjs_owner_configure_puppet_hierarchy(
    MWXSceneQuickJSOwner *owner, const int32_t *parents, const double *layer_to_world,
    char *diagnostic, size_t diagnostic_capacity
);
MWXSceneQuickJSResult mwx_scene_quickjs_owner_set_puppet_bone_name(
    MWXSceneQuickJSOwner *owner,
    uint32_t bone_index,
    const char *name,
    size_t name_length,
    char *diagnostic,
    size_t diagnostic_capacity
);
MWXSceneQuickJSResult mwx_scene_quickjs_owner_puppet_bone_mutation_at(
    MWXSceneQuickJSOwner *owner,
    size_t index,
    MWXSceneQuickJSPuppetBoneMutation *mutation,
    char *diagnostic,
    size_t diagnostic_capacity
);

// Layer mutations remain visible to subsequent callbacks in the same frame.
// The host commits or discards this owner-local transaction after Swift
// admission and surface submission decide whether the frame is safe to keep.
void mwx_scene_quickjs_owner_commit_layer_mutations(
    MWXSceneQuickJSOwner *owner
);

void mwx_scene_quickjs_owner_discard_layer_mutations(
    MWXSceneQuickJSOwner *owner
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_layer_mutation_at(
    MWXSceneQuickJSOwner *owner,
    size_t index,
    MWXSceneQuickJSLayerMutation *mutation,
    char *diagnostic,
    size_t diagnostic_capacity
);

size_t mwx_scene_quickjs_owner_video_command_count(
    const MWXSceneQuickJSOwner *owner
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_video_command_at(
    const MWXSceneQuickJSOwner *owner,
    size_t index,
    MWXSceneQuickJSVideoCommand *command,
    char *diagnostic,
    size_t diagnostic_capacity
);

size_t mwx_scene_quickjs_owner_texture_animation_command_count(
    const MWXSceneQuickJSOwner *owner
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_texture_animation_command_at(
    const MWXSceneQuickJSOwner *owner,
    size_t index,
    MWXSceneQuickJSTextureAnimationCommand *command,
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

MWXSceneQuickJSResult mwx_scene_quickjs_domain_commit_layer_snapshot(
    MWXSceneQuickJSDomain *domain,
    char *diagnostic,
    size_t diagnostic_capacity
);

void mwx_scene_quickjs_domain_abort_layer_snapshot(
    MWXSceneQuickJSDomain *domain
);

/// Restores the last layer snapshot that was committed before the host frame
/// outcome was known. Returns true when a committed candidate was restored.
bool mwx_scene_quickjs_domain_rollback_layer_snapshot(
    MWXSceneQuickJSDomain *domain
);

/// Drops the rollback copy after the host has accepted the frame submission.
void mwx_scene_quickjs_domain_finalize_layer_snapshot(
    MWXSceneQuickJSDomain *domain
);

MWXSceneQuickJSOwner *mwx_scene_quickjs_owner_create(
    MWXSceneQuickJSDomain *domain,
    const char *source,
    size_t source_length,
    uint64_t generation,
    char *diagnostic,
    size_t diagnostic_capacity
);

MWXSceneQuickJSOwner *mwx_scene_quickjs_owner_create_with_budget(
    MWXSceneQuickJSDomain *domain,
    const char *source,
    size_t source_length,
    uint64_t generation,
    uint64_t interrupt_budget,
    MWXSceneQuickJSResult *result,
    char *diagnostic,
    size_t diagnostic_capacity
);

MWXSceneQuickJSOwner *mwx_scene_quickjs_owner_create_value_only_with_budget(
    MWXSceneQuickJSDomain *domain,
    const char *source,
    size_t source_length,
    uint64_t generation,
    uint64_t interrupt_budget,
    MWXSceneQuickJSResult *result,
    char *diagnostic,
    size_t diagnostic_capacity
);

MWXSceneQuickJSOwner *mwx_scene_quickjs_owner_create_effectful_bool_with_budget(
    MWXSceneQuickJSDomain *domain,
    const char *source,
    size_t source_length,
    uint64_t generation,
    uint64_t interrupt_budget,
    MWXSceneQuickJSResult *result,
    char *diagnostic,
    size_t diagnostic_capacity
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_configure_layer_identity(
    MWXSceneQuickJSOwner *owner,
    int64_t layer_id,
    char *diagnostic,
    size_t diagnostic_capacity
);

/// Declares whether the property this owner drives belongs to the layer itself
/// (layer/text fields) or to a component such as an effect. Only the layer
/// case rebinds `thisObject` to the layer's own object; component properties
/// keep the property-object handle that serves IThisPropertyObject.getAnimation.
MWXSceneQuickJSResult mwx_scene_quickjs_owner_set_property_object_scope(
    MWXSceneQuickJSOwner *owner,
    uint32_t property_object_is_layer,
    char *diagnostic,
    size_t diagnostic_capacity
);

/// Defines the current-property animation accessor on the owner's own layer
/// handle. Only layer/text property owners may call this: for component
/// properties the current property belongs to the component, not the layer.
bool mwx_scene_quickjs_define_property_animation_accessor(
    MWXSceneQuickJSOwner *owner
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_set_authored_layer_baseline(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    const double origin[3],
    const double scale[3],
    const double angles[3],
    char *diagnostic,
    size_t diagnostic_capacity
);

void mwx_scene_quickjs_owner_clear_authored_layer_baseline(
    MWXSceneQuickJSOwner *owner
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_add_authored_layer_mutation_baseline(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    int64_t layer_id,
    uint32_t fields,
    const double origin[3],
    const double scale[3],
    const double angles[3],
    uint32_t visible,
    const char *text,
    size_t text_length,
    const char *font,
    size_t font_length,
    double alpha,
    const double color[3],
    char *diagnostic,
    size_t diagnostic_capacity
);

void mwx_scene_quickjs_owner_clear_authored_layer_mutation_baselines(
    MWXSceneQuickJSOwner *owner
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

MWXSceneQuickJSResult mwx_scene_quickjs_owner_teardown(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json,
    size_t script_properties_length,
    const char *user_properties_json,
    size_t user_properties_length,
    uint32_t *destroy_callback_invoked,
    char *diagnostic,
    size_t diagnostic_capacity
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_teardown_with_provenance(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json,
    size_t script_properties_length,
    const char *user_properties_json,
    size_t user_properties_length,
    uint32_t *destroy_callback_invoked,
    uint32_t *destroy_callback_threw,
    char *diagnostic,
    size_t diagnostic_capacity
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_lifecycle_snapshot(
    MWXSceneQuickJSOwner *owner,
    MWXSceneQuickJSLifecycleSnapshot *snapshot
);

uint32_t mwx_scene_quickjs_owner_active_timer_count(
    MWXSceneQuickJSOwner *owner
);
MWXSceneQuickJSResult mwx_scene_quickjs_owner_read_bound_scalar(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    const char *property_name,
    size_t property_name_length,
    double *value,
    uint32_t *present,
    char *diagnostic,
    size_t diagnostic_capacity
);
MWXSceneQuickJSTimerFrameSnapshot *mwx_scene_quickjs_owner_timer_snapshot(
    MWXSceneQuickJSOwner *owner
);
bool mwx_scene_quickjs_owner_timer_restore(
    MWXSceneQuickJSOwner *owner,
    MWXSceneQuickJSTimerFrameSnapshot *snapshot
);
void mwx_scene_quickjs_owner_timer_snapshot_destroy(
    MWXSceneQuickJSTimerFrameSnapshot *snapshot,
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

MWXSceneQuickJSResult mwx_scene_quickjs_owner_update_bool_with_properties(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    uint32_t input,
    const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json,
    size_t script_properties_length,
    const char *user_properties_json,
    size_t user_properties_length,
    uint32_t *output,
    char *diagnostic,
    size_t diagnostic_capacity
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_update_effectful_bool_with_properties(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    uint32_t input,
    const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json,
    size_t script_properties_length,
    const char *user_properties_json,
    size_t user_properties_length,
    uint32_t *output,
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

MWXSceneQuickJSResult mwx_scene_quickjs_owner_initialize_primitive_with_properties(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    double input,
    uint32_t boolean_value,
    const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json,
    size_t script_properties_length,
    const char *user_properties_json,
    size_t user_properties_length,
    double *output,
    uint32_t *did_initialize,
    char *diagnostic,
    size_t diagnostic_capacity
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_initialize_vec3(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    const double input[3],
    const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json,
    size_t script_properties_length,
    const char *user_properties_json,
    size_t user_properties_length,
    double output[3],
    uint32_t *did_initialize,
    char *diagnostic,
    size_t diagnostic_capacity
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_update_string(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    const char *input,
    size_t input_length,
    const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json,
    size_t script_properties_length,
    const char *user_properties_json,
    size_t user_properties_length,
    char *output,
    size_t output_capacity,
    size_t *output_length,
    char *diagnostic,
    size_t diagnostic_capacity
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_initialize_string(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    const char *input,
    size_t input_length,
    const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json,
    size_t script_properties_length,
    const char *user_properties_json,
    size_t user_properties_length,
    char *output,
    size_t output_capacity,
    size_t *output_length,
    uint32_t *did_initialize,
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

MWXSceneQuickJSResult mwx_scene_quickjs_owner_dispatch_media_timeline(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    const MWXSceneQuickJSMediaTimelineEvent *event,
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

size_t mwx_scene_quickjs_owner_storage_mutation_count(
    const MWXSceneQuickJSOwner *owner
);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_storage_mutation_at(
    const MWXSceneQuickJSOwner *owner,
    size_t index,
    MWXSceneQuickJSStorageMutation *mutation,
    char *diagnostic,
    size_t diagnostic_capacity
);

void mwx_scene_quickjs_owner_discard_storage_transaction(
    MWXSceneQuickJSOwner *owner
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
