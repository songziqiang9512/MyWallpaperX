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

typedef struct MWXSceneQuickJSJSONEvent {
    const char *json;
    size_t length;
} MWXSceneQuickJSJSONEvent;

static JSValue freeze_argument(JSContext *context, JSValue argument) {
    MWXSceneQuickJSDomain *domain = JS_GetContextOpaque(context);
    if (domain == NULL || JS_IsException(argument)) return JS_EXCEPTION;
    JSValue input = JS_DupValue(context, argument);
    JSValue frozen = JS_Call(
        context, domain->deep_freeze, JS_UNDEFINED, 1, &input
    );
    JS_FreeValue(context, input);
    if (JS_IsException(frozen)) {
        JS_FreeValue(context, argument);
        return JS_EXCEPTION;
    }
    JS_FreeValue(context, frozen);
    return argument;
}

static JSValue json_argument(JSContext *context, const void *payload) {
    const MWXSceneQuickJSJSONEvent *event = payload;
    JSValue argument = JS_ParseJSON(
        context, event->json, event->length, "SceneScript event"
    );
    return freeze_argument(context, argument);
}

static JSValue vec3_value(
    JSContext *context,
    const double values[3]
) {
    MWXSceneQuickJSDomain *domain = JS_GetContextOpaque(context);
    if (domain == NULL) return JS_EXCEPTION;
    JSValue arguments[3] = {
        JS_NewFloat64(context, values[0]),
        JS_NewFloat64(context, values[1]),
        JS_NewFloat64(context, values[2]),
    };
    JSValue result = JS_CallConstructor(
        context, domain->vec3_constructor, 3, arguments
    );
    for (size_t index = 0; index < 3; ++index) {
        JS_FreeValue(context, arguments[index]);
    }
    return result;
}

static JSValue cursor_argument(JSContext *context, const void *payload) {
    const MWXSceneQuickJSCursorEvent *event = payload;
    const double world_values[3] = {
        event->world_x, event->world_y, event->world_z,
    };
    const double local_values[3] = {
        event->local_x, event->local_y, event->local_z,
    };
    JSValue argument = JS_NewObject(context);
    JSValue world = vec3_value(context, world_values);
    JSValue local = vec3_value(context, local_values);
    if (JS_IsException(argument) || JS_IsException(world) ||
        JS_IsException(local) || JS_DefinePropertyValueStr(
            context, argument, "worldPosition", JS_DupValue(context, world),
            JS_PROP_ENUMERABLE
        ) < 0 || JS_DefinePropertyValueStr(
            context, argument, "localPosition", JS_DupValue(context, local),
            JS_PROP_ENUMERABLE
        ) < 0) {
        JS_FreeValue(context, argument);
        JS_FreeValue(context, world);
        JS_FreeValue(context, local);
        return JS_EXCEPTION;
    }
    JS_FreeValue(context, world);
    JS_FreeValue(context, local);
    return freeze_argument(context, argument);
}

static JSValue thumbnail_argument(JSContext *context, const void *payload) {
    const MWXSceneQuickJSMediaThumbnailEvent *event = payload;
    const double primary_values[3] = {
        event->primary_red, event->primary_green, event->primary_blue,
    };
    const double secondary_values[3] = {
        event->secondary_red, event->secondary_green, event->secondary_blue,
    };
    const double tertiary_values[3] = {
        event->tertiary_red, event->tertiary_green, event->tertiary_blue,
    };
    const double text_values[3] = {
        event->text_red, event->text_green, event->text_blue,
    };
    const double high_contrast_values[3] = {
        event->high_contrast_red,
        event->high_contrast_green,
        event->high_contrast_blue,
    };
    JSValue argument = JS_NewObject(context);
    JSValue primary = vec3_value(context, primary_values);
    JSValue secondary = vec3_value(context, secondary_values);
    JSValue tertiary = vec3_value(context, tertiary_values);
    JSValue text = vec3_value(context, text_values);
    JSValue high_contrast = vec3_value(context, high_contrast_values);
    if (JS_IsException(argument) || JS_DefinePropertyValueStr(
            context,
            argument,
            "hasThumbnail",
            JS_NewBool(context, event->has_thumbnail != 0),
            JS_PROP_ENUMERABLE
        ) < 0 || JS_IsException(primary) || JS_IsException(secondary) ||
        JS_IsException(tertiary) || JS_IsException(text) ||
        JS_IsException(high_contrast) || JS_DefinePropertyValueStr(
            context, argument, "primaryColor",
            JS_DupValue(context, primary), JS_PROP_ENUMERABLE
        ) < 0 || JS_DefinePropertyValueStr(
            context, argument, "secondaryColor",
            JS_DupValue(context, secondary), JS_PROP_ENUMERABLE
        ) < 0 || JS_DefinePropertyValueStr(
            context, argument, "tertiaryColor",
            JS_DupValue(context, tertiary), JS_PROP_ENUMERABLE
        ) < 0 || JS_DefinePropertyValueStr(
            context, argument, "textColor",
            JS_DupValue(context, text), JS_PROP_ENUMERABLE
        ) < 0 || JS_DefinePropertyValueStr(
            context, argument, "highContrastColor",
            JS_DupValue(context, high_contrast), JS_PROP_ENUMERABLE
        ) < 0) {
        JS_FreeValue(context, argument);
        argument = JS_EXCEPTION;
    }
    JS_FreeValue(context, primary);
    JS_FreeValue(context, secondary);
    JS_FreeValue(context, tertiary);
    JS_FreeValue(context, text);
    JS_FreeValue(context, high_contrast);
    return freeze_argument(context, argument);
}

static bool normalized_color(double red, double green, double blue) {
    return isfinite(red) && isfinite(green) && isfinite(blue) &&
        red >= 0 && red <= 1 && green >= 0 && green <= 1 &&
        blue >= 0 && blue <= 1;
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
        ) < 0 || JS_DefinePropertyValueStr(
            context,
            argument,
            "subTitle",
            JS_NewStringLen(
                context,
                event->sub_title != NULL ? event->sub_title : "",
                event->sub_title_length
            ),
            JS_PROP_ENUMERABLE
        ) < 0 || JS_DefinePropertyValueStr(
            context,
            argument,
            "albumTitle",
            JS_NewStringLen(
                context,
                event->album_title != NULL ? event->album_title : "",
                event->album_title_length
            ),
            JS_PROP_ENUMERABLE
        ) < 0 || JS_DefinePropertyValueStr(
            context,
            argument,
            "albumArtist",
            JS_NewStringLen(
                context,
                event->album_artist != NULL ? event->album_artist : "",
                event->album_artist_length
            ),
            JS_PROP_ENUMERABLE
        ) < 0 || JS_DefinePropertyValueStr(
            context,
            argument,
            "genres",
            JS_NewStringLen(
                context,
                event->genres != NULL ? event->genres : "",
                event->genres_length
            ),
            JS_PROP_ENUMERABLE
        ) < 0 || JS_DefinePropertyValueStr(
            context,
            argument,
            "contentType",
            JS_NewStringLen(
                context,
                event->content_type != NULL ? event->content_type : "",
                event->content_type_length
            ),
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
    const char *script_properties_json,
    size_t script_properties_length,
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
            diagnostic, diagnostic_capacity, "invalid SceneScript event"
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
    if (!mwx_scene_quickjs_assign_script_properties(
            owner, script_properties_json, script_properties_length
        )) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "SceneScript properties unavailable"
        );
        owner->disabled = true;
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }

    MWXSceneQuickJSDomain *domain = owner->domain;
    JSContext *context = domain->context;
    domain->interrupted = false;
    owner->material_function_count = 0;
    owner->material_function_overflow = false;
    mwx_scene_quickjs_owner_begin_layer_mutations(owner);
    owner->animation_command_count = 0;
    owner->animation_command_overflow = false;
    MWXSceneQuickJSResult timer_result = mwx_scene_quickjs_run_due_timers(
        owner, frame, user_properties_json, user_properties_length,
        diagnostic, diagnostic_capacity
    );
    if (timer_result != MWX_SCENE_QUICKJS_OK) {
        owner->disabled = true;
        return timer_result;
    }

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
    MWXSceneQuickJSResult job_result = MWX_SCENE_QUICKJS_OK;
    if (JS_IsException(result)) {
        mwx_scene_quickjs_discard_jobs(owner);
    } else {
        job_result = mwx_scene_quickjs_drain_jobs(
            owner, diagnostic, diagnostic_capacity
        );
    }

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
    if (job_result != MWX_SCENE_QUICKJS_OK) {
        JS_FreeValue(context, result);
        owner->disabled = true;
        return job_result;
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
    if (event == NULL || event->has_thumbnail > 1 || !normalized_color(
            event->primary_red, event->primary_green, event->primary_blue
        ) || !normalized_color(
            event->secondary_red,
            event->secondary_green,
            event->secondary_blue
        ) || !normalized_color(
            event->tertiary_red, event->tertiary_green, event->tertiary_blue
        ) || !normalized_color(
            event->text_red, event->text_green, event->text_blue
        ) || !normalized_color(
            event->high_contrast_red,
            event->high_contrast_green,
            event->high_contrast_blue
        )) {
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
        NULL,
        0,
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
        NULL,
        0,
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
        event->sub_title_length > 65536 || event->album_title_length > 65536 ||
        event->album_artist_length > 65536 || event->genres_length > 65536 ||
        event->content_type_length > 65536 ||
        (event->sub_title == NULL && event->sub_title_length != 0) ||
        (event->album_title == NULL && event->album_title_length != 0) ||
        (event->album_artist == NULL && event->album_artist_length != 0) ||
        (event->genres == NULL && event->genres_length != 0) ||
        (event->content_type == NULL && event->content_type_length != 0) ||
        memchr(event->title, '\0', event->title_length) != NULL ||
        memchr(event->artist, '\0', event->artist_length) != NULL ||
        (event->sub_title != NULL && memchr(
            event->sub_title, '\0', event->sub_title_length
        ) != NULL) ||
        (event->album_title != NULL && memchr(
            event->album_title, '\0', event->album_title_length
        ) != NULL) ||
        (event->album_artist != NULL && memchr(
            event->album_artist, '\0', event->album_artist_length
        ) != NULL) ||
        (event->genres != NULL && memchr(
            event->genres, '\0', event->genres_length
        ) != NULL) ||
        (event->content_type != NULL && memchr(
            event->content_type, '\0', event->content_type_length
        ) != NULL)) {
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
        NULL,
        0,
        frame,
        user_properties_json,
        user_properties_length,
        diagnostic,
        diagnostic_capacity
    );
}

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
) {
    if (changed_properties_json == NULL || changed_properties_length == 0 ||
        changed_properties_length > 65536) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid user properties event"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    const MWXSceneQuickJSJSONEvent event = {
        .json = changed_properties_json,
        .length = changed_properties_length,
    };
    return dispatch_event(
        owner,
        expected_generation,
        "applyUserProperties",
        json_argument,
        &event,
        script_properties_json,
        script_properties_length,
        frame,
        user_properties_json,
        user_properties_length,
        diagnostic,
        diagnostic_capacity
    );
}

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
) {
    const char *callback = NULL;
    switch (kind) {
    case MWX_SCENE_QUICKJS_CURSOR_ENTER: callback = "cursorEnter"; break;
    case MWX_SCENE_QUICKJS_CURSOR_LEAVE: callback = "cursorLeave"; break;
    case MWX_SCENE_QUICKJS_CURSOR_DOWN: callback = "cursorDown"; break;
    case MWX_SCENE_QUICKJS_CURSOR_MOVE: callback = "cursorMove"; break;
    case MWX_SCENE_QUICKJS_CURSOR_UP: callback = "cursorUp"; break;
    case MWX_SCENE_QUICKJS_CURSOR_CLICK: callback = "cursorClick"; break;
    default: break;
    }
    if (callback == NULL || event == NULL) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid cursor event"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    if (!isfinite(event->world_x) || !isfinite(event->world_y) ||
        !isfinite(event->world_z) || !isfinite(event->local_x) ||
        !isfinite(event->local_y) || !isfinite(event->local_z)) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid cursor position"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    return dispatch_event(
        owner,
        expected_generation,
        callback,
        cursor_argument,
        event,
        NULL,
        0,
        frame,
        user_properties_json,
        user_properties_length,
        diagnostic,
        diagnostic_capacity
    );
}
