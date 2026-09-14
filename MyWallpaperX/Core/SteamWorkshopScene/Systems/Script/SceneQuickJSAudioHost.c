#include "SceneQuickJSInternal.h"

#include <math.h>
#include <stdint.h>

static bool supported_resolution(uint32_t resolution) {
    return resolution == 16 || resolution == 32 || resolution == 64;
}

static JSValue new_float32_array(JSContext *context, uint32_t count) {
    JSValue length = JS_NewUint32(context, count);
    JSValue array = JS_NewTypedArray(
        context, 1, &length, JS_TYPED_ARRAY_FLOAT32
    );
    JS_FreeValue(context, length);
    return array;
}

static JSValue register_audio_buffers(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv
) {
    (void)this_value;
    MWXSceneQuickJSDomain *domain = JS_GetContextOpaque(context);
    if (domain == NULL || domain->module_owner == NULL || domain->callback_active) {
        return JS_ThrowTypeError(
            context, "registerAudioBuffers is only available during module evaluation"
        );
    }
    uint32_t resolution = 16;
    int32_t requested = 0;
    if (argc > 1 || (argc == 1 && (
            JS_ToInt32(context, &requested, argv[0]) < 0 || requested < 0
        ))) {
        return JS_ThrowTypeError(context, "invalid audio resolution");
    }
    if (argc == 1) resolution = (uint32_t)requested;
    if (!supported_resolution(resolution)) {
        return JS_ThrowRangeError(context, "audio resolution must be 16, 32 or 64");
    }
    MWXSceneQuickJSOwner *owner = domain->module_owner;
    if (owner->value_only) {
        return JS_ThrowTypeError(
            context, "audio is unavailable to value-only SceneScript owners"
        );
    }
    for (size_t index = 0; index < owner->audio_registration_count; ++index) {
        MWXSceneQuickJSAudioRegistration *registration =
            &owner->audio_registrations[index];
        if (registration->resolution == resolution) {
            return JS_DupValue(context, registration->object);
        }
    }
    if (owner->audio_registration_count >=
        MWX_SCENE_QUICKJS_MAX_AUDIO_REGISTRATIONS) {
        return JS_ThrowRangeError(context, "audio registration budget exceeded");
    }

    MWXSceneQuickJSAudioRegistration *registration =
        &owner->audio_registrations[owner->audio_registration_count];
    registration->object = JS_NewObject(context);
    registration->left = new_float32_array(context, resolution);
    registration->right = new_float32_array(context, resolution);
    registration->average = new_float32_array(context, resolution);
    if (JS_IsException(registration->object) ||
        JS_IsException(registration->left) ||
        JS_IsException(registration->right) ||
        JS_IsException(registration->average) ||
        JS_DefinePropertyValueStr(
            context, registration->object, "left",
            JS_DupValue(context, registration->left), JS_PROP_ENUMERABLE
        ) < 0 ||
        JS_DefinePropertyValueStr(
            context, registration->object, "right",
            JS_DupValue(context, registration->right), JS_PROP_ENUMERABLE
        ) < 0 ||
        JS_DefinePropertyValueStr(
            context, registration->object, "average",
            JS_DupValue(context, registration->average), JS_PROP_ENUMERABLE
        ) < 0) {
        JS_FreeValue(context, registration->object);
        JS_FreeValue(context, registration->left);
        JS_FreeValue(context, registration->right);
        JS_FreeValue(context, registration->average);
        registration->object = JS_UNDEFINED;
        registration->left = JS_UNDEFINED;
        registration->right = JS_UNDEFINED;
        registration->average = JS_UNDEFINED;
        return JS_EXCEPTION;
    }
    registration->resolution = resolution;
    owner->audio_registration_count += 1;
    return JS_DupValue(context, registration->object);
}

bool mwx_scene_quickjs_bind_module_engine_host(
    MWXSceneQuickJSOwner *owner,
    JSValue *previous_global_engine
) {
    if (owner == NULL || owner->domain == NULL || previous_global_engine == NULL ||
        owner->domain->module_owner != NULL) {
        return false;
    }
    JSContext *context = owner->domain->context;
    JSValue engine = JS_NewObject(context);
    JSValue registration = JS_NewCFunction(
        context, register_audio_buffers, "registerAudioBuffers", 1
    );
    const int read_only = JS_PROP_ENUMERABLE;
    if (JS_IsException(engine) || JS_IsException(registration) ||
        JS_DefinePropertyValueStr(
            context, engine, "AUDIO_RESOLUTION_16", JS_NewInt32(context, 16),
            read_only
        ) < 0 ||
        JS_DefinePropertyValueStr(
            context, engine, "AUDIO_RESOLUTION_32", JS_NewInt32(context, 32),
            read_only
        ) < 0 ||
        JS_DefinePropertyValueStr(
            context, engine, "AUDIO_RESOLUTION_64", JS_NewInt32(context, 64),
            read_only
        ) < 0 ||
        JS_DefinePropertyValueStr(
            context, engine, "registerAudioBuffers",
            JS_DupValue(context, registration), read_only
        ) < 0 || !mwx_scene_quickjs_install_asset_engine(owner, engine)) {
        JS_FreeValue(context, engine);
        JS_FreeValue(context, registration);
        return false;
    }
    JS_FreeValue(context, registration);
    if (!mwx_scene_quickjs_bind_active_engine(
            owner->domain, engine, previous_global_engine
        )) {
        JS_FreeValue(context, engine);
        return false;
    }
    owner->domain->module_owner = owner;
    return true;
}

bool mwx_scene_quickjs_restore_module_engine_host(
    MWXSceneQuickJSOwner *owner,
    JSValue previous_global_engine
) {
    if (owner == NULL || owner->domain == NULL ||
        owner->domain->module_owner != owner) {
        return false;
    }
    owner->domain->module_owner = NULL;
    return mwx_scene_quickjs_restore_active_engine(
        owner->domain, previous_global_engine
    );
}

void mwx_scene_quickjs_destroy_audio_host(MWXSceneQuickJSOwner *owner) {
    if (owner == NULL || owner->domain == NULL || owner->domain->context == NULL) {
        return;
    }
    JSContext *context = owner->domain->context;
    for (size_t index = 0; index < owner->audio_registration_count; ++index) {
        MWXSceneQuickJSAudioRegistration *registration =
            &owner->audio_registrations[index];
        JS_FreeValue(context, registration->object);
        JS_FreeValue(context, registration->left);
        JS_FreeValue(context, registration->right);
        JS_FreeValue(context, registration->average);
    }
    owner->audio_registration_count = 0;
}

size_t mwx_scene_quickjs_owner_audio_registration_count(
    const MWXSceneQuickJSOwner *owner
) {
    return owner != NULL ? owner->audio_registration_count : 0;
}

static bool set_audio_values(
    JSContext *context,
    JSValueConst array,
    const float *left,
    const float *right,
    size_t count,
    bool average
) {
    for (size_t index = 0; index < count; ++index) {
        double value = average
            ? ((double)left[index] + (double)right[index]) * 0.5
            : (double)left[index];
        if (JS_SetPropertyUint32(
                context, array, (uint32_t)index, JS_NewFloat64(context, value)
            ) < 0) {
            return false;
        }
    }
    return true;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_refresh_audio_resolution(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    uint32_t resolution,
    const float *left,
    const float *right,
    size_t count,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner == NULL || owner->value_only || left == NULL || right == NULL ||
        !supported_resolution(resolution) || count != resolution) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid SceneScript audio snapshot"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    if (owner->generation != expected_generation) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "stale SceneScript owner generation"
        );
        return MWX_SCENE_QUICKJS_STALE_OWNER;
    }
    if (owner->disabled) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "SceneScript owner is disabled"
        );
        return MWX_SCENE_QUICKJS_DISABLED;
    }
    for (size_t index = 0; index < count; ++index) {
        if (!isfinite(left[index]) || left[index] < 0 ||
            !isfinite(right[index]) || right[index] < 0) {
            mwx_scene_quickjs_write_diagnostic(
                diagnostic, diagnostic_capacity,
                "invalid SceneScript audio sample"
            );
            return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
        }
    }
    for (size_t index = 0; index < owner->audio_registration_count; ++index) {
        MWXSceneQuickJSAudioRegistration *registration =
            &owner->audio_registrations[index];
        if (registration->resolution != resolution) continue;
        JSContext *context = owner->domain->context;
        if (!set_audio_values(
                context, registration->left, left, right, count, false
            ) ||
            !set_audio_values(
                context, registration->right, right, left, count, false
            ) ||
            !set_audio_values(
                context, registration->average, left, right, count, true
            )) {
            mwx_scene_quickjs_write_exception(
                owner->domain, diagnostic, diagnostic_capacity
            );
            owner->disabled = true;
            return MWX_SCENE_QUICKJS_EXCEPTION;
        }
    }
    return MWX_SCENE_QUICKJS_OK;
}
