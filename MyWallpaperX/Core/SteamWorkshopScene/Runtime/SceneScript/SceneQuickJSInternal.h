#ifndef MWX_SCENE_QUICKJS_INTERNAL_H
#define MWX_SCENE_QUICKJS_INTERNAL_H

#include "SceneQuickJS.h"
#include "QuickJSNG/quickjs.h"

#include <stdbool.h>

#define MWX_SCENE_QUICKJS_MAX_MATERIAL_FUNCTION_MUTATIONS 16
#define MWX_SCENE_QUICKJS_MAX_ANIMATION_COMMANDS 16
#define MWX_SCENE_QUICKJS_MAX_MATERIAL_FUNCTION_NAME 128
#define MWX_SCENE_QUICKJS_MAX_EFFECTS 1024
#define MWX_SCENE_QUICKJS_MAX_EFFECT_NAME 256
#define MWX_SCENE_QUICKJS_MAX_LAYERS 4096
#define MWX_SCENE_QUICKJS_MAX_LAYER_NAME 256
#define MWX_SCENE_QUICKJS_MAX_DYNAMIC_LAYERS 64
#define MWX_SCENE_QUICKJS_MAX_SCENE_DYNAMIC_LAYERS 256
#define MWX_SCENE_QUICKJS_MAX_LAYER_TEXT 4096
#define MWX_SCENE_QUICKJS_MAX_LAYER_FONT 1024
#define MWX_SCENE_QUICKJS_MAX_LAYER_ASSET_PATH 1024
#define MWX_SCENE_QUICKJS_MAX_AUDIO_REGISTRATIONS 3
#define MWX_SCENE_QUICKJS_MAX_TIMERS 32
#define MWX_SCENE_QUICKJS_MAX_JOBS_PER_CALLBACK 64
#define MWX_SCENE_QUICKJS_MAX_UNHANDLED_REJECTIONS 16
#define MWX_SCENE_QUICKJS_MAX_OWNER_SOURCE_BYTES (256u * 1024u)
#define MWX_SCENE_QUICKJS_MAX_VIDEO_COMMANDS 64
#define MWX_SCENE_QUICKJS_MAX_VIDEO_ENDED_CALLBACKS 16
#define MWX_SCENE_QUICKJS_MAX_STORAGE_MUTATIONS 64
#define MWX_SCENE_QUICKJS_MAX_STORAGE_KEY_BYTES 256
#define MWX_SCENE_QUICKJS_MAX_STORAGE_VALUE_BYTES (64u * 1024u)

typedef struct MWXSceneQuickJSMaterialFunctionMutationRecord {
    uint32_t effect_index;
    char function_name[MWX_SCENE_QUICKJS_MAX_MATERIAL_FUNCTION_NAME];
} MWXSceneQuickJSMaterialFunctionMutationRecord;

typedef struct MWXSceneQuickJSLayerRecord {
    int64_t layer_id;
    int64_t parent_id;
    char *name;
    char *text;
    char *font;
    char *asset_path;
    double authored_origin[3];
    double current_origin[3];
    double scale[3];
    double angles[3];
    double color[3];
    double alpha;
    double point_size;
    int32_t order_index;
    uint64_t owner_identity;
    uint64_t dirty_owner_identity;
    bool visible;
    bool has_parent;
    bool dynamic;
    bool destroyed;
    bool dirty;
    bool configured;
    bool text_mutable;
    bool video_available;
    bool video_loop;
    bool video_is_playing;
    double video_duration;
    double video_rate;
    double video_current_time;
    uint64_t video_ended_generation;
} MWXSceneQuickJSLayerRecord;

typedef struct MWXSceneQuickJSStagedLayerSnapshot {
    char *text;
    char *font;
    double current_origin[3];
    double scale[3];
    double angles[3];
    double color[3];
    double alpha;
    double point_size;
    bool visible;
    bool runtime_fields_staged;
    bool video_available;
    bool video_loop;
    bool video_is_playing;
    double video_duration;
    double video_rate;
    double video_current_time;
    uint64_t video_ended_generation;
} MWXSceneQuickJSStagedLayerSnapshot;

typedef struct MWXSceneQuickJSAuthoredLayerMutationRecord {
    uint32_t layer_index;
    uint32_t fields;
    double origin[3];
    double scale[3];
    double angles[3];
    bool visible;
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

struct MWXSceneQuickJSDomain {
    JSRuntime *runtime;
    JSContext *context;
    JSValue vec2_constructor;
    JSValue vec3_constructor;
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
    uint64_t interrupt_budget;
    uint64_t owner_creation_budget;
    bool interrupted;
    MWXSceneQuickJSCancellationCheck cancellation_check;
    void *cancellation_opaque;
    MWXSceneQuickJSLayerRecord *layers;
    uint32_t layer_count;
    uint32_t authored_layer_count;
    uint64_t layer_snapshot_generation;
    MWXSceneQuickJSStagedLayerSnapshot *pending_layer_snapshot;
    uint64_t pending_layer_snapshot_generation;
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
};

struct MWXSceneQuickJSOwner {
    MWXSceneQuickJSDomain *domain;
    JSValue module;
    uint64_t identity;
    uint64_t generation;
    bool initialized;
    bool disabled;
    bool value_only;
    bool effectful_boolean;
    bool teardown_started;
    uint32_t destroy_callback_count;
    JSValue material_function_layer;
    JSValue scene_handle;
    JSValue object_handle;
    size_t material_function_count;
    bool material_function_overflow;
    size_t animation_command_count;
    bool animation_command_overflow;
    size_t video_command_count;
    bool video_command_overflow;
    size_t video_ended_callback_count;
    bool current_animation_available;
    uint32_t target_layer_index;
    bool target_layer_configured;
    uint32_t effect_count;
    char **effect_names;
    size_t audio_registration_count;
    uint64_t next_timer_identity;
    double timer_runtime;
    bool timer_runtime_initialized;
    MWXSceneQuickJSTimerRecord timers[MWX_SCENE_QUICKJS_MAX_TIMERS];
    bool rejection_overflow;
    size_t layer_mutation_count;
    size_t storage_mutation_count;
    size_t storage_mutation_bytes;
    bool storage_mutation_overflow;
    bool storage_transaction_active;
    char *storage_screen_identity;
    bool authored_layer_baseline_available;
    double authored_layer_baseline_origin[3];
    double authored_layer_baseline_scale[3];
    double authored_layer_baseline_angles[3];
    size_t authored_layer_mutation_count;
    MWXSceneQuickJSAuthoredLayerMutationRecord authored_layer_mutations[
        MWX_SCENE_QUICKJS_MAX_DYNAMIC_LAYERS
    ];
    size_t authored_layer_mutation_baseline_count;
    MWXSceneQuickJSAuthoredLayerMutationRecord authored_layer_mutation_baselines[
        MWX_SCENE_QUICKJS_MAX_DYNAMIC_LAYERS
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
    MWXSceneQuickJSAnimationCommand animation_commands[
        MWX_SCENE_QUICKJS_MAX_ANIMATION_COMMANDS
    ];
    MWXSceneQuickJSVideoCommand video_commands[
        MWX_SCENE_QUICKJS_MAX_VIDEO_COMMANDS
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
bool mwx_scene_quickjs_install_owner_handles(MWXSceneQuickJSOwner *owner);
bool mwx_scene_quickjs_install_layer_handles(MWXSceneQuickJSOwner *owner);
bool mwx_scene_quickjs_install_layer_handle_class(MWXSceneQuickJSDomain *domain);
bool mwx_scene_quickjs_install_asset_engine(
    MWXSceneQuickJSOwner *owner,
    JSValue engine
);
bool mwx_scene_quickjs_install_object_handle(MWXSceneQuickJSOwner *owner);
void mwx_scene_quickjs_destroy_owner_handles(MWXSceneQuickJSOwner *owner);
void mwx_scene_quickjs_owner_begin_layer_mutations(MWXSceneQuickJSOwner *owner);
void mwx_scene_quickjs_owner_discard_layer_mutations(MWXSceneQuickJSOwner *owner);
void mwx_scene_quickjs_owner_remove_dynamic_layers(MWXSceneQuickJSOwner *owner);
bool mwx_scene_quickjs_dispatch_video_ended_callbacks(
    MWXSceneQuickJSOwner *owner
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

#endif
