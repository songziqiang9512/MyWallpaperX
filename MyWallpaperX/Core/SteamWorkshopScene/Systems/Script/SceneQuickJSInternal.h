#ifndef MWX_SCENE_QUICKJS_INTERNAL_H
#define MWX_SCENE_QUICKJS_INTERNAL_H

#include "SceneQuickJS.h"
#include "QuickJSNG/quickjs.h"

#include <stdbool.h>

#define MWX_SCENE_QUICKJS_MAX_MATERIAL_FUNCTION_MUTATIONS 16
#define MWX_SCENE_QUICKJS_MAX_ANIMATION_COMMANDS 16
#define MWX_SCENE_QUICKJS_MAX_NAMED_ANIMATIONS 4096
#define MWX_SCENE_QUICKJS_MAX_ANIMATION_NAME 256
#define MWX_SCENE_QUICKJS_MAX_PUPPET_ANIMATION_COMMANDS 64
#define MWX_SCENE_QUICKJS_MAX_PUPPET_ANIMATION_CALLBACKS 16
#define MWX_SCENE_QUICKJS_MAX_MATERIAL_FUNCTION_NAME 128
#define MWX_SCENE_QUICKJS_MAX_EFFECTS 1024
#define MWX_SCENE_QUICKJS_MAX_EFFECT_NAME 256
#define MWX_SCENE_QUICKJS_MAX_LAYERS 4096
#define MWX_SCENE_QUICKJS_MAX_LAYER_NAME 256
#define MWX_SCENE_QUICKJS_MAX_LAYER_MUTATIONS 256
#define MWX_SCENE_QUICKJS_MAX_SCENE_DYNAMIC_LAYERS 256
#define MWX_SCENE_QUICKJS_MAX_LAYER_TEXT 4096
#define MWX_SCENE_QUICKJS_MAX_LAYER_FONT 1024
#define MWX_SCENE_QUICKJS_MAX_LAYER_ASSET_PATH 1024
#define MWX_SCENE_QUICKJS_MAX_AUDIO_REGISTRATIONS 3
#define MWX_SCENE_QUICKJS_MAX_TIMERS 32
#define MWX_SCENE_QUICKJS_MAX_JOBS_PER_CALLBACK 64
#define MWX_SCENE_QUICKJS_MAX_UNHANDLED_REJECTIONS 16
#define MWX_SCENE_QUICKJS_MAX_OWNER_SOURCE_BYTES (256u * 1024u)
#define MWX_SCENE_QUICKJS_MAX_MEDIA_PLAYBACK_COMMANDS 64
#define MWX_SCENE_QUICKJS_MAX_TEXTURE_ANIMATION_COMMANDS 64
#define MWX_SCENE_QUICKJS_MAX_PARTICLE_PLAYBACK_COMMANDS 64
#define MWX_SCENE_QUICKJS_MAX_VIDEO_ENDED_CALLBACKS 16
#define MWX_SCENE_QUICKJS_MAX_STORAGE_MUTATIONS 64
#define MWX_SCENE_QUICKJS_MAX_STORAGE_KEY_BYTES 256
#define MWX_SCENE_QUICKJS_MAX_STORAGE_VALUE_BYTES (64u * 1024u)
#define MWX_SCENE_QUICKJS_MAX_DYNAMIC_LAYER_OPERATIONS \
    (MWX_SCENE_QUICKJS_MAX_LAYERS * 2)
#define MWX_SCENE_QUICKJS_MAX_PUPPET_BONES 256
#define MWX_SCENE_QUICKJS_MAX_PUPPET_BONE_MUTATIONS 256

enum MWXSceneQuickJSDynamicLayerTopologyOperationKind {
    MWX_SCENE_QUICKJS_DYNAMIC_LAYER_CREATE = 1,
    MWX_SCENE_QUICKJS_DYNAMIC_LAYER_SORT = 2,
    MWX_SCENE_QUICKJS_DYNAMIC_LAYER_DESTROY = 3,
};

enum MWXSceneQuickJSDynamicLayerTopologyOperationState {
    MWX_SCENE_QUICKJS_DYNAMIC_LAYER_OPERATION_PENDING = 0,
    MWX_SCENE_QUICKJS_DYNAMIC_LAYER_OPERATION_COMMITTED = 1,
    MWX_SCENE_QUICKJS_DYNAMIC_LAYER_OPERATION_DISCARDED = 2,
};

typedef struct MWXSceneQuickJSMaterialFunctionMutationRecord {
    uint32_t effect_index;
    char function_name[MWX_SCENE_QUICKJS_MAX_MATERIAL_FUNCTION_NAME];
} MWXSceneQuickJSMaterialFunctionMutationRecord;

typedef struct MWXSceneQuickJSAnimationCommandRecord {
    MWXSceneQuickJSAnimationCommand command;
    uint32_t target_index;
    uint64_t callback_epoch;
    uint32_t ordinal;
} MWXSceneQuickJSAnimationCommandRecord;

typedef struct MWXSceneQuickJSNamedAnimationRecord {
    uint32_t target_index;
    uint32_t layer_index;
    int64_t layer_id;
    size_t name_length;
    char name[MWX_SCENE_QUICKJS_MAX_ANIMATION_NAME + 1];
    uint32_t scene_only;
} MWXSceneQuickJSNamedAnimationRecord;

enum LayerProperty {
    LAYER_ORIGIN,
    LAYER_SIZE,
    LAYER_SCALE,
    LAYER_ANGLES,
    LAYER_VISIBLE,
    LAYER_SOLID,
    LAYER_PERSPECTIVE,
    LAYER_ALPHA,
    LAYER_COLOR,
    LAYER_TEXT,
    LAYER_POINT_SIZE,
    LAYER_FONT,
    LAYER_ID,
    LAYER_NAME,
};

// Shared identity for ordinary layer access and its particle-instance projection.
typedef struct MWXSceneQuickJSLayerAccessHandle {
    MWXSceneQuickJSDomain *domain;
    uint64_t owner_identity;
    uint32_t layer_index;
    uint64_t callback_epoch;
    bool owner_target;
    bool persistent;
    // Non-null only during the synchronous CClosure ownership transfer.
    bool *construction_finalized;
} MWXSceneQuickJSLayerAccessHandle;

enum MWXSceneQuickJSLayerAccessScope {
    MWX_SCENE_QUICKJS_LAYER_OWNER_BOUND,
    MWX_SCENE_QUICKJS_LAYER_AUTHORED_REFERENCE,
};


typedef struct MWXSceneQuickJSTextTemplate {
    JSValue wrapper;
    uint8_t *bytecode;
    size_t bytecode_length;
    char *authored_seed;
    char *current_input;
    char *script_properties;
    size_t input_length, properties_length;
    uint64_t generation;
    uint32_t kind;
    uint32_t alias_count;
    struct MWXSceneQuickJSDynamicImageAliasRecord *aliases;
    bool inputs_available;
} MWXSceneQuickJSTextTemplate;

typedef struct MWXSceneQuickJSLayerRecord {
    int64_t layer_id;
    int64_t parent_id;
    MWXSceneQuickJSTextTemplate *text_template;
    uint64_t text_template_identity, text_property_owner_identity;
    char *name;
    char *text;
    char *font;
    char *asset_path;
    uint8_t *initial_configuration;
    size_t initial_configuration_length;
    uint32_t effect_count;
    char **effect_names;
    uint8_t *effect_visible;
    double authored_origin[3];
    double current_origin[3];
    double size[2];
    bool size_available;
    double world_transform[16];
    double scale[3];
    double angles[3];
    double color[3];
    double alpha;
    bool particle_instance_available;
    double particle_alpha;
    double point_size;
    int32_t order_index;
    uint64_t owner_identity;
    uint64_t dirty_owner_identity;
    uint32_t dirty_fields;
    bool visible;
    bool solid;
    uint32_t perspective;
    bool has_parent;
    bool dynamic;
    bool destroyed;
    bool dirty;
    bool configured;
    bool text_mutable;
    bool world_transform_available;
    bool video_available;
    bool video_loop;
    bool video_is_playing;
    bool sound_available;
    bool sound_is_playing;
    double video_duration;
    double video_rate;
    double video_current_time;
    uint64_t video_ended_generation;
    MWXSceneQuickJSParticlePlaybackState particle_playback;
    bool texture_animation_available;
    bool texture_animation_is_playing;
    bool texture_animation_shared_is_playing;
    uint32_t texture_animation_frame_count;
    double texture_animation_duration;
    double texture_animation_rate;
    double texture_animation_current_frame;
    double texture_animation_shared_rate;
    double texture_animation_shared_current_frame;
} MWXSceneQuickJSLayerRecord;

typedef struct MWXSceneQuickJSDynamicImageRecord {
    char *model_path;
    char *identity_key;
    double natural_size[2];
    bool autosize;
    MWXSceneQuickJSPreparedLayerKind resource_kind;
} MWXSceneQuickJSDynamicImageRecord;

typedef struct MWXSceneQuickJSTextCloneSnapshot {
    uint32_t layer_index;
    int64_t layer_id;
    char *text;
    struct MWXSceneQuickJSTextCloneSnapshot *next;
} MWXSceneQuickJSTextCloneSnapshot;

typedef struct MWXSceneQuickJSStagedLayerSnapshot {
    char *text;
    char *font;
    uint8_t *effect_visible;
    bool text_replaced;
    bool font_replaced;
    double current_origin[3];
    double world_transform[16];
    double scale[3];
    double angles[3];
    double color[3];
    double alpha;
    bool particle_instance_available;
    double particle_alpha;
    double point_size;
    bool visible;
    bool solid;
    uint32_t perspective;
    bool destroyed;
    bool world_transform_available;
    bool runtime_fields_staged;
    bool video_available;
    bool video_loop;
    bool video_is_playing;
    bool sound_available;
    bool sound_is_playing;
    double video_duration;
    double video_rate;
    double video_current_time;
    uint64_t video_ended_generation;
    MWXSceneQuickJSParticlePlaybackState particle_playback;
    bool texture_animation_available;
    bool texture_animation_is_playing;
    bool texture_animation_shared_is_playing;
    uint32_t texture_animation_frame_count;
    double texture_animation_duration;
    double texture_animation_rate;
    double texture_animation_current_frame;
    double texture_animation_shared_rate;
    double texture_animation_shared_current_frame;
} MWXSceneQuickJSStagedLayerSnapshot;

typedef struct MWXSceneQuickJSAuthoredLayerMutationRecord {
    uint8_t *effect_visible; /* 2 means untouched */
    uint32_t layer_index;
    uint32_t fields;
    bool destroyed;
    double origin[3];
    double scale[3];
    double angles[3];
    double alpha;
    double particle_alpha;
    double point_size;
    double color[3];
    bool visible;
    bool solid;
    uint32_t perspective;
    char *text;
    char *font;
} MWXSceneQuickJSAuthoredLayerMutationRecord;

typedef struct MWXSceneQuickJSVideoEndedCallbackRecord {
    int64_t layer_id;
    uint64_t delivered_generation;
    JSValue callback;
    bool active;
} MWXSceneQuickJSVideoEndedCallbackRecord;

typedef struct MWXSceneQuickJSAudioRegistration {
    uint32_t resolution;
    JSValue object;
    JSValue left;
    JSValue right;
    JSValue average;
} MWXSceneQuickJSAudioRegistration;

typedef struct MWXSceneQuickJSTimerRecord {
    uint64_t identity;
    double remaining_seconds;
    double interval_seconds;
    JSValue callback;
    bool repeating;
    bool active;
} MWXSceneQuickJSTimerRecord;

typedef struct MWXSceneQuickJSPuppetAnimationIdentity {
    int64_t layer_id;
    uint32_t animation_layer_index;
    int64_t animation_layer_id;
    uint32_t has_animation_layer_id;
} MWXSceneQuickJSPuppetAnimationIdentity;

typedef struct MWXSceneQuickJSPuppetAnimationRecord {
    MWXSceneQuickJSPuppetAnimationSnapshot snapshot;
    uint64_t incarnation;
    uint64_t event_published_sequence;
    bool available;
} MWXSceneQuickJSPuppetAnimationRecord;

typedef struct MWXSceneQuickJSPuppetPendingEvent {
    MWXSceneQuickJSPuppetAnimationIdentity identity;
    uint64_t incarnation;
    char *name;
    int64_t frame;
} MWXSceneQuickJSPuppetPendingEvent;

// Only the nested owner's typed Boolean value is provisional here. Playback
// fields are read from the domain mirror plus the existing command journal.
typedef struct MWXSceneQuickJSPuppetVisibilityValue {
    bool present;
    bool value;
    size_t journal_cutoff;
} MWXSceneQuickJSPuppetVisibilityValue;

struct MWXSceneQuickJSTimerFrameSnapshot {
    double timer_runtime;
    bool timer_runtime_initialized;
    MWXSceneQuickJSTimerRecord timers[MWX_SCENE_QUICKJS_MAX_TIMERS];
    JSValue puppet_animation_callbacks[MWX_SCENE_QUICKJS_MAX_PUPPET_ANIMATION_CALLBACKS];
    size_t puppet_animation_callback_count;
    uint64_t puppet_animation_delivered_sequence;
    size_t puppet_event_cursor;
    uint64_t puppet_event_queue_epoch;
    size_t puppet_animation_command_count;
    size_t puppet_animation_command_read_start;
    size_t puppet_animation_registration_count;
    bool puppet_animation_command_overflow;
    MWXSceneQuickJSPuppetVisibilityValue puppet_animation_visibility;
    bool puppet_animation_visibility_staged;
};

typedef struct MWXSceneQuickJSRejectionRecord {
    JSValue promise;
    JSValue reason;
    bool active;
} MWXSceneQuickJSRejectionRecord;

typedef struct MWXSceneQuickJSStorageMutationRecord {
    uint32_t kind;
    bool global_scope;
    char *key;
    size_t key_length;
    char *json;
    size_t json_length;
} MWXSceneQuickJSStorageMutationRecord;

// Dynamic layer records are exposed to JavaScript during a callback, so the
// callback must be able to read its own writes. Keep only the first value
// touched by an owner; topology edits are replayed from the domain-level
// operation journal so multiple owners can mutate one frame safely.
typedef struct MWXSceneQuickJSDynamicLayerValueBaseline {
    uint32_t layer_index;
    uint32_t dirty_fields;
    double current_origin[3];
    double scale[3];
    double angles[3];
    double color[3];
    double alpha;
    double point_size;
    char *text;
    char *font;
    bool visible;
    bool solid;
    uint32_t perspective;
} MWXSceneQuickJSDynamicLayerValueBaseline;

typedef struct MWXSceneQuickJSDynamicLayerTopologyOperation {
    uint64_t owner_identity;
    uint32_t layer_index;
    int32_t order_index;
    uint32_t kind;
    uint32_t state;
} MWXSceneQuickJSDynamicLayerTopologyOperation;

struct MWXSceneQuickJSDomain {
    JSRuntime *runtime;
    JSContext *context;
    JSValue vec2_constructor;
    JSValue vec3_constructor;
    JSValue mat4_constructor;
    JSValue deep_freeze;
    JSValue script_property_assigner;
    JSValue active_engine;
    JSValue active_layer;
    JSValue active_scene;
    JSValue active_object;
    JSValue shared_value;
    JSValue user_properties_snapshot;
    char *user_properties_json;
    size_t user_properties_json_length;
    bool user_properties_snapshot_valid;
    JSClassID layer_handle_class_id;
    JSClassID asset_handle_class_id;
    MWXSceneQuickJSParticleEmission particle_emission;
    MWXSceneQuickJSParticleBoundary particle_boundary;
    void *particle_emission_opaque;
    uint64_t particle_native_work;
    size_t particle_native_limit, particle_native_reserved;
    bool particle_frame_active;
    uint64_t interrupt_budget;
    uint64_t owner_creation_budget;
    bool interrupted;
    MWXSceneQuickJSCancellationCheck cancellation_check;
    void *cancellation_opaque;
    MWXSceneQuickJSLayerRecord *layers;
    uint32_t layer_count;
    uint32_t authored_layer_count;
    MWXSceneQuickJSAssetPathNormalizer asset_path_normalizer;
    MWXSceneQuickJSDynamicImageRecord *dynamic_image_resources;
    uint32_t dynamic_image_resource_count;
    bool dynamic_image_catalog_configured;
    bool defaults_to_perspective;
    MWXSceneQuickJSNamedAnimationRecord *named_animations;
    size_t named_animation_count;
    bool named_animations_configured;
    // All callbacks run serially, but their dynamic topology edits remain
    // provisional until the host frame barrier. The baseline plus operation
    // journal lets the domain replay only committed/pending owner ranges when
    // one owner is rejected, without a second layer/renderer registry.
    bool dynamic_layer_topology_transaction_active;
    uint32_t dynamic_layer_topology_baseline_layer_count;
    size_t dynamic_layer_topology_baseline_order_count;
    uint32_t dynamic_layer_topology_baseline_order[
        MWX_SCENE_QUICKJS_MAX_LAYERS
    ];
    uint8_t dynamic_layer_topology_baseline_active[
        MWX_SCENE_QUICKJS_MAX_LAYERS
    ];
    size_t dynamic_layer_topology_operation_count;
    MWXSceneQuickJSDynamicLayerTopologyOperation
        dynamic_layer_topology_operations[
            MWX_SCENE_QUICKJS_MAX_DYNAMIC_LAYER_OPERATIONS
        ];
    size_t dynamic_layer_transaction_participant_count;
    size_t dynamic_layer_topology_participant_count;
    uint64_t layer_snapshot_generation;
    MWXSceneQuickJSTextCloneSnapshot *pending_text_clone_snapshot;
    MWXSceneQuickJSTextCloneSnapshot *rollback_text_clone_snapshot;
    size_t pending_text_clone_count;
    MWXSceneQuickJSStagedLayerSnapshot *pending_layer_snapshot;
    uint64_t pending_layer_snapshot_generation;
    bool pending_defaults_to_perspective;
    MWXSceneQuickJSStagedLayerSnapshot *rollback_layer_snapshot;
    uint64_t rollback_layer_snapshot_generation;
    bool rollback_defaults_to_perspective;
    int32_t *rollback_layer_order;
    uint32_t rollback_layer_order_count;
    MWXSceneQuickJSOwner *puppet_animation_owners;
    MWXSceneQuickJSPuppetAnimationRecord *puppet_animations;
    size_t puppet_animation_count;
    uint64_t puppet_animation_incarnation_issuer;
    uint64_t next_owner_identity;
    uint64_t callback_epoch;
    bool callback_active;
    bool frame_input_active;
    bool value_only_guard_active;
    MWXSceneQuickJSFrameInput active_frame_input;
    MWXSceneQuickJSOwner *active_owner;
    MWXSceneQuickJSOwner *module_owner;
    MWXSceneQuickJSStorageRead storage_read;
    void *storage_opaque;
    char *storage_screen_identity;
    uint64_t callback_epoch_issuer;
    unsigned text_clone_depth;
    MWXSceneQuickJSOwner *committed_text_clone_head, *committed_text_clone_tail;
};

typedef struct MWXSceneQuickJSDynamicImageAliasRecord {
    char *authored_path;
    char *model_path;
} MWXSceneQuickJSDynamicImageAliasRecord;

struct MWXSceneQuickJSOwner {
    MWXSceneQuickJSDomain *domain;
    JSValue module;
    uint64_t identity;
    uint64_t generation;
    JSValue text_template_source;
    uint8_t *text_template_bytecode;
    size_t text_template_bytecode_length;
    MWXSceneQuickJSOwner *provisional_text_creator;
    MWXSceneQuickJSOwner *text_clone_children, *text_clone_children_tail, *text_clone_next;
    uint64_t text_clone_template_identity, text_clone_creator_identity;
    int64_t text_clone_layer_id;
    bool text_clone_failed;
    bool initialized;
    bool initialization_pending;
    MWXSceneQuickJSTimerFrameSnapshot *initialization_timers;
    bool disabled;
    bool retryable_user_property_callback;
    bool value_only;
    bool effectful_boolean;
    MWXSceneQuickJSDynamicImageAliasRecord *dynamic_image_aliases;
    uint32_t dynamic_image_alias_count;
    /// Set when the property this owner drives belongs to the layer itself
    /// (layer/text fields) instead of an effect, particle or material
    /// component. `thisObject` then binds to the layer's own object so its
    /// writes travel the layer mutation journal rather than a look-alike
    /// property store.
    bool property_object_is_layer;
    bool teardown_started;
    uint32_t destroy_callback_count;
    JSValue material_function_layer;
    JSValue scene_handle;
    JSValue object_handle;
    size_t material_function_count;
    bool material_function_overflow;
    size_t animation_command_count;
    bool animation_command_overflow;
    size_t media_playback_command_count;
    bool media_playback_command_overflow;
    // Query projection only: commands before this callback retain their journal
    // order but cannot stand in for a published playback observation.
    uint64_t media_playback_callback_epoch;
    size_t media_playback_callback_start;
    size_t particle_playback_command_count;
    bool particle_playback_command_overflow;
    MWXSceneQuickJSParticlePlaybackCommand particle_playback_commands[MWX_SCENE_QUICKJS_MAX_PARTICLE_PLAYBACK_COMMANDS];
    size_t texture_animation_command_count;
    bool texture_animation_command_overflow;
    size_t video_ended_callback_count;
    bool current_animation_available;
    bool puppet_animation_configured, puppet_animation_available;
    bool puppet_handles_events;
    uint32_t puppet_event_failure;
    size_t puppet_event_count, puppet_event_cursor;
    uint64_t puppet_event_queue_epoch;
    MWXSceneQuickJSPuppetPendingEvent *puppet_events;
    bool puppet_animation_command_overflow, puppet_animation_visibility_staged;
    MWXSceneQuickJSOwner *puppet_animation_next;
    MWXSceneQuickJSPuppetAnimationIdentity puppet_animation_identity;
    uint64_t puppet_animation_incarnation;
    size_t puppet_animation_catalog_index;
    bool puppet_animation_catalog_bound;
    MWXSceneQuickJSPuppetVisibilityValue puppet_animation_visibility;
    size_t puppet_animation_command_count, puppet_animation_callback_count;
    size_t puppet_animation_command_read_start;
    size_t puppet_animation_registration_count;
    uint64_t puppet_animation_delivered_sequence;
    MWXSceneQuickJSPuppetAnimationCommand puppet_animation_commands[MWX_SCENE_QUICKJS_MAX_PUPPET_ANIMATION_COMMANDS];
    JSValue puppet_animation_callbacks[MWX_SCENE_QUICKJS_MAX_PUPPET_ANIMATION_CALLBACKS];
    MWXSceneQuickJSTimerFrameSnapshot *puppet_animation_baseline;
    uint32_t target_layer_index;
    bool target_layer_configured;
    /// Set for owners whose property is an effect's visibility. The object
    /// handle exposes a writable `visible` that stages into the slot below;
    /// the update passthrough consumes it as the frame's published value.
    bool effect_visibility_configured;
    int64_t effect_visibility_layer_id;
    int32_t effect_visibility_effect_index;
    bool effect_visibility_staged;
    bool effect_visibility_staged_visible;
    /// The getter reads staged writes, then this frame's candidate, then the
    /// committed value (initialized from the authored, not prepared, seed).
    bool effect_visibility_pending;
    bool effect_visibility_pending_visible;
    bool effect_visibility_committed_visible;
    uint32_t effect_count;
    char **effect_names;
    size_t audio_registration_count;
    uint64_t next_timer_identity;
    double timer_runtime;
    bool timer_runtime_initialized;
    MWXSceneQuickJSTimerRecord timers[MWX_SCENE_QUICKJS_MAX_TIMERS];
    bool rejection_overflow;
    size_t layer_mutation_count;
    size_t puppet_bone_mutation_count;
    int64_t puppet_bone_layer_id;
    uint32_t puppet_bone_count;
    int32_t puppet_bone_parent[MWX_SCENE_QUICKJS_MAX_PUPPET_BONES];
    double puppet_layer_to_world[16];
    char *puppet_bone_names[MWX_SCENE_QUICKJS_MAX_PUPPET_BONES];
    double puppet_bone_world[MWX_SCENE_QUICKJS_MAX_PUPPET_BONES][16];
    /* Query locals and physical render locals share one transaction. */
    double puppet_bone_local[MWX_SCENE_QUICKJS_MAX_PUPPET_BONES][16];
    double (*puppet_bone_render_local)[16];
    uint32_t puppet_bone_render_capacity;
    bool puppet_bone_transaction_active;
    double puppet_bone_world_baseline[MWX_SCENE_QUICKJS_MAX_PUPPET_BONES][16];
    double puppet_bone_local_baseline[MWX_SCENE_QUICKJS_MAX_PUPPET_BONES][16];
    /* Borrowed tail of the render-local allocation, sized by capacity. */
    double (*puppet_bone_render_local_baseline)[16];
    MWXSceneQuickJSPuppetBoneMutation puppet_bone_mutations[
        MWX_SCENE_QUICKJS_MAX_PUPPET_BONE_MUTATIONS
    ];
    bool dynamic_layer_transaction_active;
    bool dynamic_layer_topology_participating;
    size_t dynamic_layer_created_count;
    uint32_t dynamic_layer_created_indices[MWX_SCENE_QUICKJS_MAX_LAYERS];
    size_t dynamic_layer_value_baseline_count;
    MWXSceneQuickJSDynamicLayerValueBaseline dynamic_layer_value_baselines[
        MWX_SCENE_QUICKJS_MAX_LAYER_MUTATIONS
    ];
    size_t storage_mutation_count;
    size_t storage_mutation_bytes;
    bool storage_mutation_overflow;
    bool storage_transaction_active;
    char *storage_screen_identity;
    bool authored_layer_baseline_available;
    double authored_layer_baseline_origin[3];
    double authored_layer_baseline_scale[3];
    double authored_layer_baseline_angles[3];
    bool layer_mutation_overflow;
    size_t authored_layer_mutation_count;
    MWXSceneQuickJSAuthoredLayerMutationRecord authored_layer_mutations[
        MWX_SCENE_QUICKJS_MAX_LAYER_MUTATIONS
    ];
    size_t authored_layer_mutation_baseline_count;
    MWXSceneQuickJSAuthoredLayerMutationRecord authored_layer_mutation_baselines[
        MWX_SCENE_QUICKJS_MAX_LAYER_MUTATIONS
    ];
    MWXSceneQuickJSRejectionRecord rejections[
        MWX_SCENE_QUICKJS_MAX_UNHANDLED_REJECTIONS
    ];
    MWXSceneQuickJSAudioRegistration audio_registrations[
        MWX_SCENE_QUICKJS_MAX_AUDIO_REGISTRATIONS
    ];
    MWXSceneQuickJSMaterialFunctionMutationRecord material_functions[
        MWX_SCENE_QUICKJS_MAX_MATERIAL_FUNCTION_MUTATIONS
    ];
    MWXSceneQuickJSAnimationCommandRecord animation_commands[
        MWX_SCENE_QUICKJS_MAX_ANIMATION_COMMANDS
    ];
    MWXSceneQuickJSMediaPlaybackCommand media_playback_commands[
        MWX_SCENE_QUICKJS_MAX_MEDIA_PLAYBACK_COMMANDS
    ];
    MWXSceneQuickJSTextureAnimationCommand texture_animation_commands[
        MWX_SCENE_QUICKJS_MAX_TEXTURE_ANIMATION_COMMANDS
    ];
    MWXSceneQuickJSVideoEndedCallbackRecord video_ended_callbacks[
        MWX_SCENE_QUICKJS_MAX_VIDEO_ENDED_CALLBACKS
    ];
    MWXSceneQuickJSStorageMutationRecord storage_mutations[
        MWX_SCENE_QUICKJS_MAX_STORAGE_MUTATIONS
    ];
};

void mwx_scene_quickjs_write_diagnostic(
    char *diagnostic,
    size_t capacity,
    const char *message
);
void mwx_scene_quickjs_write_exception(
    MWXSceneQuickJSDomain *domain,
    char *diagnostic,
    size_t capacity
);

bool mwx_scene_quickjs_install_value_host(MWXSceneQuickJSDomain *domain);
bool mwx_scene_quickjs_install_storage_host(MWXSceneQuickJSDomain *domain);
void mwx_scene_quickjs_owner_discard_storage_transaction(MWXSceneQuickJSOwner *owner);
void mwx_scene_quickjs_destroy_storage_owner(MWXSceneQuickJSOwner *owner);
MWXSceneQuickJSResult mwx_scene_quickjs_owner_update_primitive_with_properties(
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
    char *diagnostic,
    size_t diagnostic_capacity
);
bool mwx_scene_quickjs_install_active_engine_host(
    MWXSceneQuickJSDomain *domain
);
bool mwx_scene_quickjs_install_owner_handle_globals(
    MWXSceneQuickJSDomain *domain
);
bool mwx_scene_quickjs_install_owner_handles(
    MWXSceneQuickJSOwner *owner,
    const char **failed_phase
);
bool mwx_scene_quickjs_install_layer_handles(MWXSceneQuickJSOwner *owner);
JSValue mwx_scene_quickjs_layer_access_closure(
    JSContext *context, JSCClosure *function, const char *name,
    int length, int magic, MWXSceneQuickJSLayerAccessHandle *handle
);
bool mwx_scene_quickjs_install_layer_handle_class(MWXSceneQuickJSDomain *domain);
bool mwx_scene_quickjs_install_asset_engine(
    MWXSceneQuickJSOwner *owner,
    JSValue engine
);
bool mwx_scene_quickjs_install_object_handle(MWXSceneQuickJSOwner *owner);
bool mwx_scene_quickjs_define_layer_animation_accessor(
    MWXSceneQuickJSOwner *owner, JSValue layer, uint32_t layer_index,
    bool current_property
);
bool mwx_scene_quickjs_define_scene_animation_accessor(
    MWXSceneQuickJSOwner *owner, JSValue scene
);
void mwx_scene_quickjs_destroy_owner_handles(MWXSceneQuickJSOwner *owner);
void mwx_scene_quickjs_owner_begin_layer_mutations(MWXSceneQuickJSOwner *owner);
void mwx_scene_quickjs_owner_discard_layer_mutations(MWXSceneQuickJSOwner *owner);
void mwx_scene_quickjs_compact_layer_order(MWXSceneQuickJSDomain *domain);
bool mwx_scene_quickjs_owner_remove_dynamic_layers(MWXSceneQuickJSOwner *owner);
MWXSceneQuickJSResult mwx_scene_quickjs_dispatch_video_ended_callbacks(
    MWXSceneQuickJSOwner *owner, char *diagnostic, size_t diagnostic_capacity
);
void mwx_scene_quickjs_clear_video_ended_callbacks(
    MWXSceneQuickJSOwner *owner
);
bool mwx_scene_quickjs_bind_owner_handles(
    MWXSceneQuickJSOwner *owner,
    JSValue *previous_layer,
    JSValue *previous_scene,
    JSValue *previous_object
);
bool mwx_scene_quickjs_restore_owner_handles(
    MWXSceneQuickJSOwner *owner,
    JSValue previous_layer,
    JSValue previous_scene,
    JSValue previous_object
);
bool mwx_scene_quickjs_bind_active_engine(
    MWXSceneQuickJSDomain *domain,
    JSValue engine,
    JSValue *previous_engine
);
bool mwx_scene_quickjs_restore_active_engine(
    MWXSceneQuickJSDomain *domain,
    JSValue previous_engine
);
bool mwx_scene_quickjs_bind_frame_engine_host(
    MWXSceneQuickJSOwner *owner,
    const MWXSceneQuickJSFrameInput *frame,
    const char *user_properties_json,
    size_t user_properties_length,
    JSValue *previous_global_engine
);
bool mwx_scene_quickjs_restore_frame_engine_host(
    MWXSceneQuickJSOwner *owner,
    JSValue previous_global_engine
);
bool mwx_scene_quickjs_bind_module_engine_host(
    MWXSceneQuickJSOwner *owner,
    JSValue *previous_global_engine
);
bool mwx_scene_quickjs_restore_module_engine_host(
    MWXSceneQuickJSOwner *owner,
    JSValue previous_global_engine
);
bool mwx_scene_quickjs_install_timer_engine(
    MWXSceneQuickJSOwner *owner,
    JSValue engine
);
MWXSceneQuickJSResult mwx_scene_quickjs_run_due_timers(
    MWXSceneQuickJSOwner *owner,
    const MWXSceneQuickJSFrameInput *frame,
    const char *user_properties_json,
    size_t user_properties_length,
    char *diagnostic,
    size_t diagnostic_capacity
);
void mwx_scene_quickjs_destroy_timer_host(MWXSceneQuickJSOwner *owner);
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
void mwx_scene_quickjs_install_job_host(MWXSceneQuickJSDomain *domain);
MWXSceneQuickJSResult mwx_scene_quickjs_drain_jobs(
    MWXSceneQuickJSOwner *owner,
    char *diagnostic,
    size_t diagnostic_capacity
);
void mwx_scene_quickjs_discard_jobs(MWXSceneQuickJSOwner *owner);
bool mwx_scene_quickjs_owner_has_job_residue(MWXSceneQuickJSOwner *owner);
void mwx_scene_quickjs_destroy_job_host(MWXSceneQuickJSOwner *owner);
void mwx_scene_quickjs_destroy_audio_host(MWXSceneQuickJSOwner *owner);
void mwx_scene_quickjs_begin_callback(MWXSceneQuickJSOwner *owner);
void mwx_scene_quickjs_end_callback(MWXSceneQuickJSOwner *owner);
MWXSceneQuickJSResult mwx_scene_quickjs_exception_result(
    MWXSceneQuickJSDomain *domain,
    char *diagnostic,
    size_t diagnostic_capacity
);
bool mwx_scene_quickjs_assign_script_properties(
    MWXSceneQuickJSOwner *owner,
    const char *json,
    size_t length
);


// Internal layer responsibilities share the existing Domain/Owner state and ABI.
int32_t mwx_scene_quickjs_layer_active_count(MWXSceneQuickJSDomain *domain);
bool mwx_scene_quickjs_layer_append_dynamic_layer_topology_operation(
    MWXSceneQuickJSOwner *owner,
    uint32_t kind,
    uint32_t layer_index,
    int32_t order_index
);
const double *mwx_scene_quickjs_layer_authored_transform_value(
    const MWXSceneQuickJSOwner *owner,
    const MWXSceneQuickJSAuthoredLayerMutationRecord *mutation,
    const MWXSceneQuickJSAuthoredLayerMutationRecord *baseline,
    uint32_t layer_index,
    uint32_t field,
    const double staged[3],
    const double current[3]
);
bool mwx_scene_quickjs_layer_callback_owns(MWXSceneQuickJSOwner *owner);
bool mwx_scene_quickjs_layer_define_get_texture_animation(
    JSContext *context, JSValue layer, MWXSceneQuickJSOwner *owner,
    uint32_t index, bool owner_target, bool persistent
);
bool mwx_scene_quickjs_layer_define_get_video_texture(
    JSContext *context, JSValue layer, MWXSceneQuickJSOwner *owner,
    uint32_t index, bool owner_target, bool persistent
);
bool mwx_scene_quickjs_layer_define_layer_playback(JSContext *context, JSValue layer,
    MWXSceneQuickJSOwner *owner, uint32_t index, bool owner_target, bool persistent);
bool mwx_scene_quickjs_layer_define_property(
    JSContext *context, JSValue layer, MWXSceneQuickJSOwner *owner,
    uint32_t index, bool owner_target, bool persistent,
    const char *name, enum LayerProperty property, bool writable
);
bool mwx_scene_quickjs_layer_define_puppet_bone_functions(
    JSContext *context, JSValue layer, MWXSceneQuickJSOwner *owner,
    uint32_t index, bool owner_target, bool persistent
);
void mwx_scene_quickjs_layer_discard_last_dynamic_layer_topology_operation(
    MWXSceneQuickJSOwner *owner
);
bool mwx_scene_quickjs_layer_ensure_dynamic_layer_transaction(
    MWXSceneQuickJSOwner *owner
);
void mwx_scene_quickjs_layer_finalize_asset_handle(JSRuntime *runtime, JSValue value);
bool mwx_scene_quickjs_layer_journal_dynamic_layer_creation(
    MWXSceneQuickJSOwner *owner,
    uint32_t layer_index
);
bool mwx_scene_quickjs_layer_journal_dynamic_layer_value(
    MWXSceneQuickJSOwner *owner,
    uint32_t layer_index
);
JSValue mwx_scene_quickjs_layer_make_asset_handle(
    JSContext *context,
    MWXSceneQuickJSDomain *domain,
    const char *path,
    size_t length
);
JSValue mwx_scene_quickjs_layer_make_layer_handle(
    JSContext *context, MWXSceneQuickJSOwner *owner, uint32_t index, bool persistent
);
JSValue mwx_scene_quickjs_layer_make_mat4(JSContext *context, MWXSceneQuickJSDomain *domain,
                         const double matrix[16]);
JSValue mwx_scene_quickjs_layer_make_vec3(JSContext *context, MWXSceneQuickJSDomain *domain, const double v[3]);
bool mwx_scene_quickjs_layer_mark_dirty(MWXSceneQuickJSOwner *owner, MWXSceneQuickJSLayerRecord *record);
bool mwx_scene_quickjs_install_scene_layer_handle(MWXSceneQuickJSOwner *owner);
bool mwx_scene_quickjs_layer_read_vec3(
    JSContext *context, JSValueConst value, double output[3],
    bool *numeric_nonfinite
);
const char *mwx_scene_quickjs_layer_registered_asset_path(
    MWXSceneQuickJSDomain *domain,
    JSValueConst value
);
MWXSceneQuickJSLayerRecord *mwx_scene_quickjs_layer_resolve_layer_argument(
    JSContext *context, MWXSceneQuickJSOwner *owner, JSValueConst value
);
int32_t mwx_scene_quickjs_layer_storage_at_order(MWXSceneQuickJSDomain *domain, int32_t order);
bool mwx_scene_quickjs_layer_valid_asset_path(const char *path, size_t length, size_t maximum_length);

JSValue mwx_scene_quickjs_create_owner_layer_handle(MWXSceneQuickJSOwner *owner);

bool mwx_scene_quickjs_read_vector(JSContext *, JSValueConst, double *, uint32_t, bool);
MWXSceneQuickJSLayerRecord *mwx_scene_quickjs_layer_record_for_handle(
    MWXSceneQuickJSLayerAccessHandle *, enum MWXSceneQuickJSLayerAccessScope);
MWXSceneQuickJSOwner *mwx_scene_quickjs_bound_handle_owner(
    JSContext *, const MWXSceneQuickJSLayerAccessHandle *, bool module_evaluation);
JSValue mwx_scene_quickjs_owner_bound_closure(
    MWXSceneQuickJSOwner *, JSCClosure *, const char *, int length, int magic);
bool mwx_scene_quickjs_define_particle_instance(MWXSceneQuickJSOwner *, JSValue,
    uint32_t, bool owner_target, bool persistent);
MWXSceneQuickJSAuthoredLayerMutationRecord *mwx_scene_quickjs_stage_authored_mutation(MWXSceneQuickJSOwner *, uint32_t);
MWXSceneQuickJSAuthoredLayerMutationRecord *mwx_scene_quickjs_authored_mutation_for_layer(MWXSceneQuickJSOwner *, uint32_t);
MWXSceneQuickJSAuthoredLayerMutationRecord *mwx_scene_quickjs_authored_mutation_baseline_for_layer(MWXSceneQuickJSOwner *, uint32_t);
bool mwx_scene_quickjs_define_layer_effect_access(MWXSceneQuickJSOwner *, JSValue, uint32_t);

JSValue mwx_scene_quickjs_puppet_animation_handle(MWXSceneQuickJSOwner *owner);
bool mwx_scene_quickjs_define_puppet_animation_lookup(MWXSceneQuickJSOwner *owner, JSValue layer);
void mwx_scene_quickjs_puppet_animation_finish_transaction(MWXSceneQuickJSOwner *owner, bool commit);
void mwx_scene_quickjs_destroy_puppet_animation_host(MWXSceneQuickJSOwner *owner);
void mwx_scene_quickjs_prepare_puppet_animation_visibility(MWXSceneQuickJSOwner *owner, double *output);
MWXSceneQuickJSResult mwx_scene_quickjs_dispatch_puppet_animation_events(
    MWXSceneQuickJSOwner *owner, const MWXSceneQuickJSFrameInput *frame,
    const char *properties, size_t properties_length, const char *users, size_t users_length,
    double *value, char *diagnostic, size_t diagnostic_capacity);
MWXSceneQuickJSResult mwx_scene_quickjs_dispatch_puppet_animation_end(
    MWXSceneQuickJSOwner *owner, const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json, size_t script_properties_length,
    const char *user_properties_json, size_t user_properties_length,
    char *diagnostic, size_t diagnostic_capacity);
bool mwx_scene_quickjs_assign_script_properties(MWXSceneQuickJSOwner *owner, const char *json, size_t length);

void mwx_scene_quickjs_capture_text_source(MWXSceneQuickJSOwner *, JSValueConst, const char *, size_t);
void mwx_scene_quickjs_release_text_source(MWXSceneQuickJSOwner *);
bool mwx_scene_quickjs_layer_owns_dynamic_target(MWXSceneQuickJSOwner *, const MWXSceneQuickJSLayerRecord *);
MWXSceneQuickJSOwner *mwx_scene_quickjs_create_prepared_text_owner(
    MWXSceneQuickJSDomain *, JSValueConst, uint64_t, MWXSceneQuickJSResult *, char *, size_t);
MWXSceneQuickJSOwner *mwx_scene_quickjs_text_transaction_owner(MWXSceneQuickJSOwner *);
bool mwx_scene_quickjs_domain_charge_work(MWXSceneQuickJSDomain *, uint64_t);
uint64_t mwx_scene_quickjs_match_text_template(MWXSceneQuickJSDomain *, JSValueConst);
bool mwx_scene_quickjs_text_template_matches_identity(MWXSceneQuickJSDomain *, JSValueConst, uint64_t);
char *mwx_scene_quickjs_text_template_input(MWXSceneQuickJSDomain *, uint64_t);
bool mwx_scene_quickjs_text_clone_can_begin(MWXSceneQuickJSOwner *, uint64_t);
bool mwx_scene_quickjs_activate_text_clone(MWXSceneQuickJSOwner *, uint32_t, uint64_t);
void mwx_scene_quickjs_finish_text_clones(MWXSceneQuickJSOwner *, bool);
bool mwx_scene_quickjs_text_exports_supported(MWXSceneQuickJSOwner *);
void mwx_scene_quickjs_destroy_text_templates(MWXSceneQuickJSDomain *);
void mwx_scene_quickjs_destroy_text_clone_queue(MWXSceneQuickJSDomain *);

#endif
