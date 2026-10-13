#ifndef MWX_SCENE_SCRIPT_QUICKJS_FIXTURE_H
#define MWX_SCENE_SCRIPT_QUICKJS_FIXTURE_H

#include "SceneQuickJS.h"

/* One Domain and the original owner lifetimes span every ordered case family.
 * The final cleanup keeps the original destruction order. No product state
 * or engine logic is stored here. */
typedef struct {
    MWXSceneQuickJSDomain *domain;
    char diagnostic[512];
    int failures;
    int storage_reads;
    MWXSceneQuickJSResult value_only_create_result;

    /* RuntimeCases */
    MWXSceneQuickJSOwner *cross_owner;
    MWXSceneQuickJSOwner *isolated;
    MWXSceneQuickJSOwner *console_mutation;
    MWXSceneQuickJSOwner *positive;
    MWXSceneQuickJSOwner *metadata_only;
    MWXSceneQuickJSOwner *time_of_day;
    MWXSceneQuickJSOwner *invalid_wemath_mix;
    MWXSceneQuickJSOwner *wemath_mix;
    MWXSceneQuickJSOwner *wemath_angles;
    MWXSceneQuickJSOwner *wevector;
    MWXSceneQuickJSOwner *invalid_wevector;
    MWXSceneQuickJSOwner *immutable_surface;
    MWXSceneQuickJSOwner *surface_input;
    MWXSceneQuickJSOwner *invalid_surface;
    MWXSceneQuickJSOwner *global_surface;
    MWXSceneQuickJSOwner *budget;
    MWXSceneQuickJSOwner *invalid_effect;
    MWXSceneQuickJSOwner *immutable_handle;
    MWXSceneQuickJSOwner *mutation_overflow;
    MWXSceneQuickJSOwner *bad_return;
    MWXSceneQuickJSOwner *number_return;
    MWXSceneQuickJSOwner *nan_return;
    MWXSceneQuickJSOwner *string_return;
    MWXSceneQuickJSOwner *callback_error;
    MWXSceneQuickJSOwner *immutable_frame;

    /* ValueCases */
    MWXSceneQuickJSOwner *vec3;
    MWXSceneQuickJSOwner *vec3_return_contract;
    MWXSceneQuickJSOwner *vec3_noop_mutation;
    MWXSceneQuickJSOwner *vec3_mix;
    MWXSceneQuickJSOwner *vec2_mix;
    MWXSceneQuickJSOwner *vec3_invalid_return;
    MWXSceneQuickJSOwner *vec3_nonfinite_return;
    MWXSceneQuickJSOwner *vec3_string_return;
    MWXSceneQuickJSOwner *wecolor;
    MWXSceneQuickJSOwner *wecolor_wrap;
    MWXSceneQuickJSOwner *wecolor_normalize;
    MWXSceneQuickJSOwner *wecolor_normalize_invalid;
    MWXSceneQuickJSOwner *immutable_user;
    MWXSceneQuickJSOwner *scalar_user;
    MWXSceneQuickJSOwner *bad_string;
    MWXSceneQuickJSOwner *numeric_string;
    MWXSceneQuickJSOwner *fractional_string;

    /* LayerReadCases */
    MWXSceneQuickJSOwner *persistent_layer;
    MWXSceneQuickJSOwner *invalid_matrix_argument;
    MWXSceneQuickJSOwner *matrix_owner;
    MWXSceneQuickJSOwner *value_only_layers;
    MWXSceneQuickJSOwner *layer_owner;
    MWXSceneQuickJSOwner *forged_layer;

    /* AnimationCases */
    MWXSceneQuickJSOwner *stale_effect;
    MWXSceneQuickJSOwner *named_animation;
    MWXSceneQuickJSOwner *media_animation;
    MWXSceneQuickJSOwner *effect_visibility;
    MWXSceneQuickJSOwner *stale_animation;
    MWXSceneQuickJSOwner *animation_owner;

    /* EventCases */
    MWXSceneQuickJSOwner *immutable_media_playback;
    MWXSceneQuickJSOwner *playback_error;
    MWXSceneQuickJSOwner *media_assign_failure;
    MWXSceneQuickJSOwner *media_playback_owner;
    MWXSceneQuickJSOwner *media_properties_owner;
    MWXSceneQuickJSOwner *media_timeline_owner;
    MWXSceneQuickJSOwner *cursor_consumer;
    MWXSceneQuickJSOwner *cursor_owner;
    MWXSceneQuickJSOwner *audio_owner;
    MWXSceneQuickJSOwner *callback_audio;

    /* JobTimerCases */
    MWXSceneQuickJSOwner *promise_owner;
    MWXSceneQuickJSOwner *promise_mutation;
    MWXSceneQuickJSOwner *event_promise;
    MWXSceneQuickJSOwner *handled_rejection;
    MWXSceneQuickJSOwner *unhandled_rejection;
    MWXSceneQuickJSOwner *job_budget;
    MWXSceneQuickJSOwner *timer_promise;
    MWXSceneQuickJSOwner *timer_owner;
    MWXSceneQuickJSOwner *timer_snapshot_owner;
    MWXSceneQuickJSOwner *interval_owner;
    MWXSceneQuickJSOwner *timer_cancel_owner;
    MWXSceneQuickJSOwner *timer_cancel_intruder;
    MWXSceneQuickJSOwner *invalid_timer;
    MWXSceneQuickJSOwner *timer_budget;
    MWXSceneQuickJSOwner *timer_exception;

    /* LayerMutationCases */
    MWXSceneQuickJSOwner *static_setter;
    MWXSceneQuickJSOwner *property_object;
    MWXSceneQuickJSOwner *component_object;
    MWXSceneQuickJSOwner *authored_self_destroy;
    MWXSceneQuickJSOwner *authored_peer_destroy;
    MWXSceneQuickJSOwner *authored_peer;
    MWXSceneQuickJSOwner *authored_observer;
    MWXSceneQuickJSOwner *missing_target_rollback;
    MWXSceneQuickJSOwner *oversized_authored_text;
    MWXSceneQuickJSOwner *nul_authored_text;
    MWXSceneQuickJSOwner *nontext_authored_text;
    MWXSceneQuickJSOwner *nonfinite_authored;
    MWXSceneQuickJSOwner *static_visible;

    /* LayerTopologyCases */
    MWXSceneQuickJSOwner *dynamic_layer;
    MWXSceneQuickJSOwner *dynamic_matrix;
    MWXSceneQuickJSOwner *dynamic_image_configuration;
    MWXSceneQuickJSOwner *destroyed_enumerated;
    MWXSceneQuickJSOwner *dynamic_intruder;
    MWXSceneQuickJSOwner *multi_owner_a;
    MWXSceneQuickJSOwner *multi_owner_b;
    MWXSceneQuickJSOwner *multi_owner_bad;
    MWXSceneQuickJSOwner *multi_owner_good;
    MWXSceneQuickJSOwner *multi_owner_observer;
    MWXSceneQuickJSOwner *dynamic_budget;
    MWXSceneQuickJSOwner *dynamic_rollback;
    MWXSceneQuickJSOwner *dynamic_rollback_observer;
    MWXSceneQuickJSOwner *dynamic_create_failure;
    MWXSceneQuickJSOwner *dynamic_explicit_discard;
    MWXSceneQuickJSOwner *dynamic_invalidate;
    MWXSceneQuickJSOwner *static_sort;
    MWXSceneQuickJSOwner *sort_order_readback;
    MWXSceneQuickJSOwner *mixed_frame;

    /* StorageCases */
    MWXSceneQuickJSOwner *storage_owner;
    MWXSceneQuickJSOwner *storage_throw;
    MWXSceneQuickJSOwner *value_storage;
    MWXSceneQuickJSOwner *missing_screen_storage;
    MWXSceneQuickJSOwner *storage_budget;
} MWXSceneScriptQuickJSFixture;

int mwx_fixture_check(int condition, const char *label, const char *diagnostic);

int mwx_fixture_update_at(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    double input,
    double frame_time,
    double runtime,
    MWXSceneQuickJSResult expected,
    double expected_output,
    const char *label
);

int mwx_fixture_update(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    double input,
    MWXSceneQuickJSResult expected,
    double expected_output,
    const char *label
);

int mwx_fixture_update_bool(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    uint32_t input,
    MWXSceneQuickJSResult expected,
    uint32_t expected_output,
    const char *label
);

int mwx_fixture_update_effectful_bool(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    uint32_t input,
    MWXSceneQuickJSResult expected,
    uint32_t expected_output,
    const char *label
);

int mwx_fixture_media_thumbnail(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    int has_thumbnail,
    MWXSceneQuickJSResult expected,
    const char *label
);

int mwx_fixture_media_playback(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    uint32_t state,
    MWXSceneQuickJSResult expected,
    const char *label
);

int mwx_fixture_media_properties(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    const char *title,
    const char *artist,
    MWXSceneQuickJSResult expected,
    const char *label
);

int mwx_fixture_media_timeline(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    double position,
    double duration,
    MWXSceneQuickJSResult expected,
    const char *label
);

int mwx_fixture_user_properties(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    const char *changed,
    const char *script_properties,
    const char *all_properties,
    MWXSceneQuickJSResult expected,
    const char *label
);

int mwx_fixture_cursor_event(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    MWXSceneQuickJSCursorEventKind kind,
    MWXSceneQuickJSResult expected,
    const char *label
);

int mwx_fixture_update_string(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    const char *input,
    MWXSceneQuickJSResult expected,
    const char *expected_output,
    const char *label
);

int mwx_fixture_refresh_audio(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    uint32_t resolution,
    const float *left,
    const float *right,
    MWXSceneQuickJSResult expected,
    const char *label
);

int mwx_fixture_update_vec3(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    const double input[3],
    const char *script_properties,
    const char *mwx_fixture_user_properties,
    MWXSceneQuickJSResult expected,
    const double expected_output[3],
    const char *label
);

int mwx_fixture_update_vec3_diagnostic_contains(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    const double input[3],
    MWXSceneQuickJSResult expected,
    const char *expected_diagnostic,
    const char *label
);

int mwx_fixture_mutation(
    MWXSceneQuickJSOwner *owner,
    size_t index,
    uint32_t expected_effect,
    const char *expected_name,
    const char *label
);

int mwx_fixture_animation_command(
    MWXSceneQuickJSOwner *owner,
    size_t index,
    MWXSceneQuickJSAnimationCommand expected,
    const char *label
);

int mwx_fixture_texture_animation_command(
    MWXSceneQuickJSOwner *owner,
    size_t index,
    uint32_t expected_kind,
    double expected_value,
    const char *label
);

int mwx_fixture_configure_effects(
    MWXSceneQuickJSOwner *owner,
    uint32_t count,
    uint32_t named_index,
    const char *name,
    const char *label
);

int mwx_fixture_configure_owner_layer(
    MWXSceneQuickJSOwner *owner,
    int64_t layer_id,
    const char *label
);

int mwx_fixture_layer_mutation(
    MWXSceneQuickJSOwner *owner,
    size_t index,
    uint32_t expected_kind,
    int expected_dynamic,
    uint32_t expected_fields,
    int64_t expected_id,
    int expected_order,
    const char *expected_text,
    const char *label
);

int mwx_fixture_configure_layers(MWXSceneQuickJSDomain *domain);

int mwx_fixture_reject_nonfinite_layer_world_snapshot(
    MWXSceneQuickJSDomain *domain
);

int mwx_fixture_commit_layer_world_snapshot(MWXSceneQuickJSDomain *domain);

int mwx_fixture_configure_texture_animation(MWXSceneQuickJSDomain *domain);

void mwx_fixture_scalar_runtime_cases(MWXSceneScriptQuickJSFixture *fixture);
void mwx_fixture_owner_failure_cases(MWXSceneScriptQuickJSFixture *fixture);
void mwx_fixture_typed_value_cases(MWXSceneScriptQuickJSFixture *fixture);
void mwx_fixture_string_value_cases(MWXSceneScriptQuickJSFixture *fixture);
void mwx_fixture_layer_catalog_admission_cases(MWXSceneScriptQuickJSFixture *fixture);
void mwx_fixture_layer_read_snapshot_cases(MWXSceneScriptQuickJSFixture *fixture);
void mwx_fixture_forged_layer_cases(MWXSceneScriptQuickJSFixture *fixture);
void mwx_fixture_texture_animation_cases(MWXSceneScriptQuickJSFixture *fixture);
void mwx_fixture_effect_animation_cases(MWXSceneScriptQuickJSFixture *fixture);
void mwx_fixture_media_cursor_cases(MWXSceneScriptQuickJSFixture *fixture);
void mwx_fixture_audio_cases(MWXSceneScriptQuickJSFixture *fixture);
void mwx_fixture_job_timer_cases(MWXSceneScriptQuickJSFixture *fixture);
void mwx_fixture_authored_layer_mutation_cases(MWXSceneScriptQuickJSFixture *fixture);
void mwx_fixture_dynamic_layer_creation_cases(MWXSceneScriptQuickJSFixture *fixture);
void mwx_fixture_dynamic_layer_transaction_cases(MWXSceneScriptQuickJSFixture *fixture);
void mwx_fixture_layer_order_cases(MWXSceneScriptQuickJSFixture *fixture);
void mwx_fixture_storage_cases(MWXSceneScriptQuickJSFixture *fixture);

#endif
