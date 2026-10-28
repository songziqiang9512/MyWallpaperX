#ifndef MWX_SCENE_QUICKJS_HOST_TYPES_H
#define MWX_SCENE_QUICKJS_HOST_TYPES_H

// Shared host ABI data contracts. Domain/owner entry points stay in SceneQuickJS.h.
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

typedef struct MWXSceneQuickJSDomain MWXSceneQuickJSDomain;
typedef struct MWXSceneQuickJSOwner MWXSceneQuickJSOwner;
// Prepared Timeline target indices belong to the Swift Program. C copies only
// this immutable lookup metadata; it owns no playback state or clock.
typedef struct MWXSceneQuickJSNamedAnimation {
    uint32_t target_index;
    int64_t layer_id;
    const char *name;
    size_t name_length;
    uint32_t scene_only; // 0: layer and scene lookup; 1: scene lookup only.
} MWXSceneQuickJSNamedAnimation;
typedef struct MWXSceneQuickJSTimerFrameSnapshot
    MWXSceneQuickJSTimerFrameSnapshot;

typedef struct MWXSceneQuickJSPuppetAnimationSnapshot {
    int64_t layer_id;
    uint32_t animation_layer_index;
    int64_t animation_layer_id;
    uint32_t has_animation_layer_id;
    int64_t animation_id;
    const char *name;
    double fps, frame_count, duration, current_frame, rate, blend;
    uint32_t is_playing, visible, supports_ended_callbacks, ended_failure;
    uint64_t ended_sequence;
} MWXSceneQuickJSPuppetAnimationSnapshot;

// Native source occurrence. Strings are borrowed during publication; the
// existing receiver owner retains any uncommitted payload.
typedef struct MWXSceneQuickJSPuppetAnimationEvent {
    int64_t layer_id, animation_layer_id;
    uint32_t animation_layer_index, has_animation_layer_id;
    uint64_t sequence;
    const char *name;
    int64_t frame;
    uint32_t failure; // zero occurrence; 1...6 native source failure
} MWXSceneQuickJSPuppetAnimationEvent;

typedef struct MWXSceneQuickJSPuppetAnimationCommand {
    int64_t layer_id;
    uint32_t animation_layer_index;
    int64_t animation_layer_id;
    uint32_t has_animation_layer_id;
    uint32_t action; // play/pause/stop/frame/rate/blend/visible = 0...6
    double value;
    uint64_t callback_epoch;
    uint32_t ordinal;
} MWXSceneQuickJSPuppetAnimationCommand;

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
    MWXSceneQuickJSOwner *owner,
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
    MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_EFFECT_VISIBILITY = 1u << 8,
    MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_SOLID = 1u << 9,
    MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PARTICLE_ALPHA = 1u << 10,
    MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PERSPECTIVE = 1u << 11,
    MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_POINT_SIZE = 1u << 12,
} MWXSceneQuickJSLayerMutationField;

typedef struct MWXSceneQuickJSLayerMutation {
    uint32_t effect_count;
    const uint8_t *effect_visible; /* 0/1 writes, 2 untouched */
    uint32_t kind;
    uint32_t dynamic;
    uint32_t fields;
    int64_t layer_id;
    int32_t order_index;
    uint32_t visible;
    uint32_t solid;
    uint32_t perspective; /* dynamic: 2 retains the inherited camera policy */
    uint32_t size_available; /* dynamic image creation geometry, read-only */
    double size[2];
    double alpha;
    double particle_alpha;
    double origin[3];
    double scale[3];
    double angles[3];
    double color[3];
    double point_size;
    const char *text;
    const char *font;
    const char *asset_path;
    uint64_t text_template_identity; /* 0: ordinary String */
} MWXSceneQuickJSLayerMutation;

typedef enum MWXSceneQuickJSPuppetBoneMutationKind {
    MWX_SCENE_QUICKJS_PUPPET_BONE_MATRIX = 0,
    MWX_SCENE_QUICKJS_PUPPET_BONE_LINEAR_IMPULSE = 1
} MWXSceneQuickJSPuppetBoneMutationKind;

/// Ordered commands in the existing layer owner transaction. Matrices are
/// parent-relative, column-major; impulses retain their authored Vec3 values.
typedef struct MWXSceneQuickJSPuppetBoneMutation {
    int64_t layer_id;
    int16_t bone_index; /* dense zero-based index, at most 255 */
    uint16_t kind;
    uint32_t ordinal; /* order within the existing domain callback epoch */
    uint64_t callback_epoch;
    union {
        double matrix[16];
        double impulse[3];
    } payload;
} MWXSceneQuickJSPuppetBoneMutation;
// text/font/asset_path are borrowed from the owner/domain. Callers must copy
// them before the next layer-mutation begin/discard, snapshot replacement, or
// owner/domain destruction.

typedef enum MWXSceneQuickJSAnimationCommand {
    MWX_SCENE_QUICKJS_ANIMATION_PLAY = 1,
    MWX_SCENE_QUICKJS_ANIMATION_PAUSE = 2,
    MWX_SCENE_QUICKJS_ANIMATION_STOP = 3,
    MWX_SCENE_QUICKJS_ANIMATION_SET_FRAME = 4
} MWXSceneQuickJSAnimationCommand;

typedef enum MWXSceneQuickJSMediaPlaybackCommandKind {
    MWX_SCENE_QUICKJS_MEDIA_PLAY = 1,
    MWX_SCENE_QUICKJS_MEDIA_PAUSE = 2,
    MWX_SCENE_QUICKJS_MEDIA_STOP = 3,
    MWX_SCENE_QUICKJS_MEDIA_SET_CURRENT_TIME = 4,
    MWX_SCENE_QUICKJS_MEDIA_SET_RATE = 5,
    MWX_SCENE_QUICKJS_MEDIA_SET_LOOP = 6
} MWXSceneQuickJSMediaPlaybackCommandKind;

typedef enum MWXSceneQuickJSMediaPlaybackDestination {
    MWX_SCENE_QUICKJS_MEDIA_VIDEO_TEXTURE = 0,
    MWX_SCENE_QUICKJS_MEDIA_SOUND_LAYER = 1
} MWXSceneQuickJSMediaPlaybackDestination;

typedef struct MWXSceneQuickJSMediaPlaybackCommand {
    uint32_t kind;
    uint32_t destination;
    int64_t layer_id;
    double number_value;
    uint32_t bool_value;
} MWXSceneQuickJSMediaPlaybackCommand;

// Prepared observations only; C owns no particle simulation or persistent intent.
typedef struct MWXSceneQuickJSParticlePlaybackState {
    uint32_t available, live, emission_pending, rearm_has_work, intent;
    uint64_t revision;
} MWXSceneQuickJSParticlePlaybackState;
typedef struct MWXSceneQuickJSParticlePlaybackCommand {
    int64_t layer_id;
    uint32_t action, ordinal, count;
    uint64_t callback_epoch;
    MWXSceneQuickJSParticlePlaybackState verified_projection;
} MWXSceneQuickJSParticlePlaybackCommand;
typedef MWXSceneQuickJSResult (*MWXSceneQuickJSParticleEmission)(
    void *opaque, MWXSceneQuickJSOwner *owner,
    const MWXSceneQuickJSParticlePlaybackCommand *command,
    MWXSceneQuickJSParticlePlaybackState *projection);
typedef void (*MWXSceneQuickJSParticleBoundary)(void *opaque, MWXSceneQuickJSOwner *owner, uint32_t discard);

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

/* The host's existing identity rule. Installed once before any owner/catalog.
 * Returns an independently malloc-allocated UTF-8 key; C owns and frees it.
 * This pure function has no opaque state and must not call author JavaScript. */
typedef char *(*MWXSceneQuickJSAssetPathNormalizer)(const char *path, size_t length);

typedef enum MWXSceneQuickJSPreparedLayerKind {
    MWX_SCENE_QUICKJS_PREPARED_LAYER_IMAGE = 0,
    MWX_SCENE_QUICKJS_PREPARED_LAYER_PUPPET = 1,
    MWX_SCENE_QUICKJS_PREPARED_LAYER_COMPOSITION = 2
} MWXSceneQuickJSPreparedLayerKind;

typedef struct MWXSceneQuickJSDynamicImageDescriptor {
    const char *model_path;
    size_t model_path_length;
    double natural_size[2];
    uint32_t autosize;
    uint32_t resource_kind;
} MWXSceneQuickJSDynamicImageDescriptor;

#endif
