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
#define MWX_SCENE_QUICKJS_MAX_AUDIO_REGISTRATIONS 3

typedef struct MWXSceneQuickJSMaterialFunctionMutationRecord {
    uint32_t effect_index;
    char function_name[MWX_SCENE_QUICKJS_MAX_MATERIAL_FUNCTION_NAME];
} MWXSceneQuickJSMaterialFunctionMutationRecord;

typedef struct MWXSceneQuickJSLayerRecord {
    int64_t layer_id;
    char *name;
    double authored_origin[3];
    double current_origin[3];
    bool configured;
} MWXSceneQuickJSLayerRecord;

typedef struct MWXSceneQuickJSAudioRegistration {
    uint32_t resolution;
    JSValue object;
    JSValue left;
    JSValue right;
    JSValue average;
} MWXSceneQuickJSAudioRegistration;

struct MWXSceneQuickJSDomain {
    JSRuntime *runtime;
    JSContext *context;
    JSValue vec3_constructor;
    JSValue deep_freeze;
    uint64_t interrupt_budget;
    bool interrupted;
    MWXSceneQuickJSLayerRecord *layers;
    uint32_t layer_count;
    uint64_t layer_snapshot_generation;
    uint64_t callback_epoch;
    bool callback_active;
    MWXSceneQuickJSOwner *active_owner;
    MWXSceneQuickJSOwner *module_owner;
};

struct MWXSceneQuickJSOwner {
    MWXSceneQuickJSDomain *domain;
    JSValue module;
    uint64_t generation;
    bool initialized;
    bool disabled;
    JSValue material_function_layer;
    JSValue scene_handle;
    JSValue object_handle;
    size_t material_function_count;
    bool material_function_overflow;
    size_t animation_command_count;
    bool animation_command_overflow;
    bool current_animation_available;
    uint32_t target_layer_index;
    bool target_layer_configured;
    uint32_t effect_count;
    char **effect_names;
    size_t audio_registration_count;
    MWXSceneQuickJSAudioRegistration audio_registrations[
        MWX_SCENE_QUICKJS_MAX_AUDIO_REGISTRATIONS
    ];
    MWXSceneQuickJSMaterialFunctionMutationRecord material_functions[
        MWX_SCENE_QUICKJS_MAX_MATERIAL_FUNCTION_MUTATIONS
    ];
    MWXSceneQuickJSAnimationCommand animation_commands[
        MWX_SCENE_QUICKJS_MAX_ANIMATION_COMMANDS
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

bool mwx_scene_quickjs_install_owner_handles(MWXSceneQuickJSOwner *owner);
bool mwx_scene_quickjs_install_object_handle(MWXSceneQuickJSOwner *owner);
void mwx_scene_quickjs_destroy_owner_handles(MWXSceneQuickJSOwner *owner);
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
