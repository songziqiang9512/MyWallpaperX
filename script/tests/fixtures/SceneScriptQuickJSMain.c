#include "SceneScriptQuickJSFixture.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

int mwx_test_layer_perspective_cases(void);
int mwx_test_legacy_capture_cases(void);

int main(void) {
    MWXSceneScriptQuickJSFixture state = {0};
    MWXSceneScriptQuickJSFixture *fixture = &state;
    fixture->domain = mwx_scene_quickjs_domain_create(
        2 * 1024 * 1024, 512 * 1024, 100000, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    if (mwx_fixture_check(fixture->domain != NULL, "domain", fixture->diagnostic)) return 1;

    fixture->failures = mwx_test_layer_perspective_cases();
    fixture->failures += mwx_test_legacy_capture_cases();
    fixture->failures += mwx_fixture_configure_layers(fixture->domain);
    fixture->failures += mwx_fixture_configure_texture_animation(fixture->domain);

    mwx_fixture_texture_animation_cases(fixture);
    mwx_fixture_layer_catalog_admission_cases(fixture);
    mwx_fixture_scalar_runtime_cases(fixture);
    mwx_fixture_typed_value_cases(fixture);
    mwx_fixture_owner_failure_cases(fixture);
    mwx_fixture_layer_read_snapshot_cases(fixture);
    mwx_fixture_effect_animation_cases(fixture);
    mwx_fixture_media_cursor_cases(fixture);
    mwx_fixture_string_value_cases(fixture);
    mwx_fixture_audio_cases(fixture);
    mwx_fixture_job_timer_cases(fixture);
    mwx_fixture_dynamic_layer_creation_cases(fixture);
    mwx_fixture_authored_layer_mutation_cases(fixture);
    mwx_fixture_forged_layer_cases(fixture);
    mwx_fixture_dynamic_layer_transaction_cases(fixture);
    mwx_fixture_storage_cases(fixture);
    mwx_fixture_layer_order_cases(fixture);

    mwx_scene_quickjs_owner_invalidate(fixture->positive);
    fixture->failures += mwx_fixture_update(
        fixture->positive, 1, 3, MWX_SCENE_QUICKJS_STALE_OWNER, 0, "stale owner"
    );

    mwx_scene_quickjs_owner_destroy(fixture->budget);
    mwx_scene_quickjs_owner_destroy(fixture->invalid_effect);
    mwx_scene_quickjs_owner_destroy(fixture->immutable_handle);
    mwx_scene_quickjs_owner_destroy(fixture->stale_effect);
    mwx_scene_quickjs_owner_destroy(fixture->named_animation);
    mwx_scene_quickjs_owner_destroy(fixture->media_animation);
    mwx_scene_quickjs_owner_destroy(fixture->effect_visibility);
    mwx_scene_quickjs_owner_destroy(fixture->immutable_media_playback);
    mwx_scene_quickjs_owner_destroy(fixture->playback_error);
    mwx_scene_quickjs_owner_destroy(fixture->media_assign_failure);
    mwx_scene_quickjs_owner_destroy(fixture->media_playback_owner);
    mwx_scene_quickjs_owner_destroy(fixture->media_properties_owner);
    mwx_scene_quickjs_owner_destroy(fixture->media_timeline_owner);
    mwx_scene_quickjs_owner_destroy(fixture->bad_string);
    mwx_scene_quickjs_owner_destroy(fixture->numeric_string);
    mwx_scene_quickjs_owner_destroy(fixture->fractional_string);
    mwx_scene_quickjs_owner_destroy(fixture->cursor_consumer);
    mwx_scene_quickjs_owner_destroy(fixture->cursor_owner);
    mwx_scene_quickjs_owner_destroy(fixture->audio_owner);
    mwx_scene_quickjs_owner_destroy(fixture->callback_audio);
    mwx_scene_quickjs_owner_destroy(fixture->promise_owner);
    mwx_scene_quickjs_owner_destroy(fixture->promise_mutation);
    mwx_scene_quickjs_owner_destroy(fixture->event_promise);
    mwx_scene_quickjs_owner_destroy(fixture->handled_rejection);
    mwx_scene_quickjs_owner_destroy(fixture->unhandled_rejection);
    mwx_scene_quickjs_owner_destroy(fixture->job_budget);
    mwx_scene_quickjs_owner_destroy(fixture->timer_promise);
    mwx_scene_quickjs_owner_destroy(fixture->timer_owner);
    mwx_scene_quickjs_owner_destroy(fixture->timer_snapshot_owner);
    mwx_scene_quickjs_owner_destroy(fixture->interval_owner);
    mwx_scene_quickjs_owner_destroy(fixture->timer_cancel_owner);
    mwx_scene_quickjs_owner_destroy(fixture->timer_cancel_intruder);
    mwx_scene_quickjs_owner_destroy(fixture->invalid_timer);
    mwx_scene_quickjs_owner_destroy(fixture->timer_budget);
    mwx_scene_quickjs_owner_destroy(fixture->timer_exception);
    mwx_scene_quickjs_owner_destroy(fixture->dynamic_layer);
    mwx_scene_quickjs_owner_destroy(fixture->dynamic_matrix);
    mwx_scene_quickjs_owner_destroy(fixture->dynamic_image_configuration);
    mwx_scene_quickjs_owner_destroy(fixture->multi_owner_a);
    mwx_scene_quickjs_owner_destroy(fixture->multi_owner_b);
    mwx_scene_quickjs_owner_destroy(fixture->multi_owner_bad);
    mwx_scene_quickjs_owner_destroy(fixture->multi_owner_good);
    mwx_scene_quickjs_owner_destroy(fixture->multi_owner_observer);
    mwx_scene_quickjs_owner_destroy(fixture->destroyed_enumerated);
    mwx_scene_quickjs_owner_destroy(fixture->dynamic_intruder);
    mwx_scene_quickjs_owner_destroy(fixture->static_sort);
    mwx_scene_quickjs_owner_destroy(fixture->sort_order_readback);
    mwx_scene_quickjs_owner_destroy(fixture->mixed_frame);
    mwx_scene_quickjs_owner_destroy(fixture->static_setter);
    mwx_scene_quickjs_owner_destroy(fixture->property_object);
    mwx_scene_quickjs_owner_destroy(fixture->component_object);
    mwx_scene_quickjs_owner_destroy(fixture->authored_self_destroy);
    mwx_scene_quickjs_owner_destroy(fixture->authored_peer_destroy);
    mwx_scene_quickjs_owner_destroy(fixture->authored_peer);
    mwx_scene_quickjs_owner_destroy(fixture->authored_observer);
    mwx_scene_quickjs_owner_destroy(fixture->missing_target_rollback);
    mwx_scene_quickjs_owner_destroy(fixture->oversized_authored_text);
    mwx_scene_quickjs_owner_destroy(fixture->nul_authored_text);
    mwx_scene_quickjs_owner_destroy(fixture->nontext_authored_text);
    mwx_scene_quickjs_owner_destroy(fixture->nonfinite_authored);
    mwx_scene_quickjs_owner_destroy(fixture->static_visible);
    mwx_scene_quickjs_owner_destroy(fixture->forged_layer);
    mwx_scene_quickjs_owner_destroy(fixture->dynamic_budget);
    mwx_scene_quickjs_owner_destroy(fixture->dynamic_rollback);
    mwx_scene_quickjs_owner_destroy(fixture->dynamic_rollback_observer);
    mwx_scene_quickjs_owner_destroy(fixture->dynamic_create_failure);
    mwx_scene_quickjs_owner_destroy(fixture->dynamic_explicit_discard);
    mwx_scene_quickjs_owner_destroy(fixture->dynamic_invalidate);
    mwx_scene_quickjs_owner_destroy(fixture->storage_owner);
    mwx_scene_quickjs_owner_destroy(fixture->storage_throw);
    mwx_scene_quickjs_owner_destroy(fixture->value_storage);
    mwx_scene_quickjs_owner_destroy(fixture->missing_screen_storage);
    mwx_scene_quickjs_owner_destroy(fixture->storage_budget);
    mwx_scene_quickjs_owner_destroy(fixture->stale_animation);
    mwx_scene_quickjs_owner_destroy(fixture->animation_owner);
    mwx_scene_quickjs_owner_destroy(fixture->persistent_layer);
    mwx_scene_quickjs_owner_destroy(fixture->invalid_matrix_argument);
    mwx_scene_quickjs_owner_destroy(fixture->matrix_owner);
    mwx_scene_quickjs_owner_destroy(fixture->value_only_layers);
    mwx_scene_quickjs_owner_destroy(fixture->layer_owner);
    mwx_scene_quickjs_owner_destroy(fixture->cross_owner);
    mwx_scene_quickjs_owner_destroy(fixture->mutation_overflow);
    mwx_scene_quickjs_owner_destroy(fixture->bad_return);
    mwx_scene_quickjs_owner_destroy(fixture->number_return);
    mwx_scene_quickjs_owner_destroy(fixture->nan_return);
    mwx_scene_quickjs_owner_destroy(fixture->string_return);
    mwx_scene_quickjs_owner_destroy(fixture->callback_error);
    mwx_scene_quickjs_owner_destroy(fixture->isolated);
    mwx_scene_quickjs_owner_destroy(fixture->console_mutation);
    mwx_scene_quickjs_owner_destroy(fixture->positive);
    mwx_scene_quickjs_owner_destroy(fixture->metadata_only);
    mwx_scene_quickjs_owner_destroy(fixture->time_of_day);
    mwx_scene_quickjs_owner_destroy(fixture->invalid_wemath_mix);
    mwx_scene_quickjs_owner_destroy(fixture->wemath_mix);
    mwx_scene_quickjs_owner_destroy(fixture->wemath_angles);
    mwx_scene_quickjs_owner_destroy(fixture->wevector);
    mwx_scene_quickjs_owner_destroy(fixture->invalid_wevector);
    mwx_scene_quickjs_owner_destroy(fixture->immutable_surface);
    mwx_scene_quickjs_owner_destroy(fixture->surface_input);
    mwx_scene_quickjs_owner_destroy(fixture->invalid_surface);
    mwx_scene_quickjs_owner_destroy(fixture->global_surface);
    mwx_scene_quickjs_owner_destroy(fixture->immutable_frame);
    mwx_scene_quickjs_owner_destroy(fixture->vec3);
    mwx_scene_quickjs_owner_destroy(fixture->vec3_return_contract);
    mwx_scene_quickjs_owner_destroy(fixture->vec3_noop_mutation);
    mwx_scene_quickjs_owner_destroy(fixture->vec3_mix);
    mwx_scene_quickjs_owner_destroy(fixture->vec2_mix);
    mwx_scene_quickjs_owner_destroy(fixture->vec3_invalid_return);
    mwx_scene_quickjs_owner_destroy(fixture->vec3_nonfinite_return);
    mwx_scene_quickjs_owner_destroy(fixture->vec3_string_return);
    mwx_scene_quickjs_owner_destroy(fixture->wecolor);
    mwx_scene_quickjs_owner_destroy(fixture->wecolor_wrap);
    mwx_scene_quickjs_owner_destroy(fixture->wecolor_normalize);
    mwx_scene_quickjs_owner_destroy(fixture->wecolor_normalize_invalid);
    mwx_scene_quickjs_owner_destroy(fixture->immutable_user);
    mwx_scene_quickjs_owner_destroy(fixture->scalar_user);
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_domain_configure_storage(
            fixture->domain, NULL, NULL, fixture->diagnostic, sizeof(fixture->diagnostic)
        ) == MWX_SCENE_QUICKJS_OK,
        "localStorage provider detached", fixture->diagnostic
    );
    mwx_scene_quickjs_domain_destroy(fixture->domain);
    return fixture->failures == 0 ? 0 : 1;
}
