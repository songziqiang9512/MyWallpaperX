#include "SceneQuickJSInternal.h"

#include <math.h>
#include <string.h>

MWXSceneQuickJSResult mwx_scene_quickjs_exception_result(
    MWXSceneQuickJSDomain *domain,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_exception(domain, diagnostic, diagnostic_capacity);
    if (domain->interrupted) return MWX_SCENE_QUICKJS_BUDGET_EXCEEDED;
    if (diagnostic != NULL && strstr(diagnostic, "out of memory") != NULL) {
        return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    }
    return MWX_SCENE_QUICKJS_EXCEPTION;
}

static bool valid_frame(const MWXSceneQuickJSFrameInput *frame) {
    return frame != NULL && isfinite(frame->time_of_day) &&
        frame->time_of_day >= 0 && frame->time_of_day <= 1 &&
        isfinite(frame->frame_time) && frame->frame_time >= 0 &&
        isfinite(frame->runtime) && frame->runtime >= 0;
}

static MWXSceneQuickJSResult callback_failure(
    MWXSceneQuickJSOwner *owner,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    MWXSceneQuickJSResult result = mwx_scene_quickjs_exception_result(
        owner->domain, diagnostic, diagnostic_capacity
    );
    if (owner->material_function_overflow || owner->animation_command_overflow) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic,
            diagnostic_capacity,
            owner->animation_command_overflow
                ? "animation command buffer exceeded"
                : "material function mutation buffer exceeded"
        );
        result = MWX_SCENE_QUICKJS_MUTATION_OVERFLOW;
    }
    owner->disabled = true;
    return result;
}

typedef JSValue (*MWXSceneQuickJSEventArgumentFactory)(
    JSContext *context,
    const void *payload
);

static JSValue thumbnail_argument(JSContext *context, const void *payload) {
    const MWXSceneQuickJSMediaThumbnailEvent *event = payload;
    JSValue argument = JS_NewObject(context);
    if (JS_IsException(argument) || JS_DefinePropertyValueStr(
            context,
            argument,
            "hasThumbnail",
            JS_NewBool(context, event->has_thumbnail != 0),
            JS_PROP_ENUMERABLE
        ) < 0) {
        JS_FreeValue(context, argument);
        return JS_EXCEPTION;
    }
    return argument;
}

static JSValue playback_argument(JSContext *context, const void *payload) {
    const MWXSceneQuickJSMediaPlaybackEvent *event = payload;
    JSValue argument = JS_NewObject(context);
    if (JS_IsException(argument) || JS_DefinePropertyValueStr(
            context,
            argument,
            "state",
            JS_NewUint32(context, event->state),
            JS_PROP_ENUMERABLE
        ) < 0) {
        JS_FreeValue(context, argument);
        return JS_EXCEPTION;
    }
    return argument;
}

static JSValue properties_argument(JSContext *context, const void *payload) {
    const MWXSceneQuickJSMediaPropertiesEvent *event = payload;
    JSValue argument = JS_NewObject(context);
    if (JS_IsException(argument) || JS_DefinePropertyValueStr(
            context,
            argument,
            "title",
            JS_NewStringLen(context, event->title, event->title_length),
            JS_PROP_ENUMERABLE
        ) < 0 || JS_DefinePropertyValueStr(
            context,
            argument,
            "artist",
            JS_NewStringLen(context, event->artist, event->artist_length),
            JS_PROP_ENUMERABLE
        ) < 0) {
        JS_FreeValue(context, argument);
        return JS_EXCEPTION;
    }
    return argument;
}

static MWXSceneQuickJSResult dispatch_event(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    const char *callback_name,
    MWXSceneQuickJSEventArgumentFactory argument_factory,
    const void *payload,
    const MWXSceneQuickJSFrameInput *frame,
    const char *user_properties_json,
    size_t user_properties_length,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner == NULL || callback_name == NULL || argument_factory == NULL ||
        payload == NULL || !valid_frame(frame)) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid SceneScript media event"
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

    MWXSceneQuickJSDomain *domain = owner->domain;
    JSContext *context = domain->context;
    domain->interrupted = false;
    owner->material_function_count = 0;
    owner->material_function_overflow = false;
    owner->animation_command_count = 0;
    owner->animation_command_overflow = false;

    JSValue function = JS_GetPropertyStr(
        context, owner->module, callback_name
    );
    if (JS_IsException(function)) {
        JS_FreeValue(context, function);
        return callback_failure(owner, diagnostic, diagnostic_capacity);
    }
    if (!JS_IsFunction(context, function)) {
        JS_FreeValue(context, function);
        return MWX_SCENE_QUICKJS_OK;
    }

    mwx_scene_quickjs_begin_callback(owner);
    JSValue previous_layer = JS_UNDEFINED;
    JSValue previous_scene = JS_UNDEFINED;
    JSValue previous_object = JS_UNDEFINED;
    if (!mwx_scene_quickjs_bind_owner_handles(
            owner, &previous_layer, &previous_scene, &previous_object
        )) {
        mwx_scene_quickjs_end_callback(owner);
        JS_FreeValue(context, function);
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "SceneScript typed handle host unavailable"
        );
        owner->disabled = true;
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    JSValue previous_engine = JS_UNDEFINED;
    if (!mwx_scene_quickjs_bind_frame_engine_host(
            owner, frame, user_properties_json, user_properties_length,
            &previous_engine
        )) {
        mwx_scene_quickjs_restore_owner_handles(
            owner, previous_layer, previous_scene, previous_object
        );
        mwx_scene_quickjs_end_callback(owner);
        JS_FreeValue(context, function);
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "SceneScript frame engine host unavailable"
        );
        owner->disabled = true;
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }

    JSValue argument = argument_factory(context, payload);
    JSValue result = JS_IsException(argument)
        ? JS_EXCEPTION
        : JS_Call(context, function, owner->module, 1, &argument);
    JS_FreeValue(context, argument);
    JS_FreeValue(context, function);

    const bool engine_restored = mwx_scene_quickjs_restore_frame_engine_host(
        owner, previous_engine
    );
    const bool handles_restored = mwx_scene_quickjs_restore_owner_handles(
        owner, previous_layer, previous_scene, previous_object
    );
    mwx_scene_quickjs_end_callback(owner);
    if (!engine_restored || !handles_restored) {
        JS_FreeValue(context, result);
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "SceneScript host restore failed"
        );
        owner->disabled = true;
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    if (JS_IsException(result)) {
        JS_FreeValue(context, result);
        return callback_failure(owner, diagnostic, diagnostic_capacity);
    }
    JS_FreeValue(context, result);
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_dispatch_media_thumbnail(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    const MWXSceneQuickJSMediaThumbnailEvent *event,
    const MWXSceneQuickJSFrameInput *frame,
    const char *user_properties_json,
    size_t user_properties_length,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    if (event == NULL || event->has_thumbnail > 1) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid media thumbnail event"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    return dispatch_event(
        owner,
        expected_generation,
        "mediaThumbnailChanged",
        thumbnail_argument,
        event,
        frame,
        user_properties_json,
        user_properties_length,
        diagnostic,
        diagnostic_capacity
    );
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_dispatch_media_playback(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    const MWXSceneQuickJSMediaPlaybackEvent *event,
    const MWXSceneQuickJSFrameInput *frame,
    const char *user_properties_json,
    size_t user_properties_length,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    if (event == NULL || event->state > 2) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid media playback event"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    return dispatch_event(
        owner,
        expected_generation,
        "mediaPlaybackChanged",
        playback_argument,
        event,
        frame,
        user_properties_json,
        user_properties_length,
        diagnostic,
        diagnostic_capacity
    );
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_dispatch_media_properties(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    const MWXSceneQuickJSMediaPropertiesEvent *event,
    const MWXSceneQuickJSFrameInput *frame,
    const char *user_properties_json,
    size_t user_properties_length,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    if (event == NULL || event->title == NULL || event->artist == NULL ||
        event->title_length > 65536 || event->artist_length > 65536 ||
        memchr(event->title, '\0', event->title_length) != NULL ||
        memchr(event->artist, '\0', event->artist_length) != NULL) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid media properties event"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    return dispatch_event(
        owner,
        expected_generation,
        "mediaPropertiesChanged",
        properties_argument,
        event,
        frame,
        user_properties_json,
        user_properties_length,
        diagnostic,
        diagnostic_capacity
    );
}
