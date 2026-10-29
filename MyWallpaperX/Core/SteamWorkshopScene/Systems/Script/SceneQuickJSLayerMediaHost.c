#include "SceneQuickJSInternal.h"

#include <math.h>
#include <float.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

enum VideoProperty {
    VIDEO_DURATION,
    VIDEO_RATE,
    VIDEO_LOOP,
};

enum VideoFunction {
    VIDEO_PLAY,
    VIDEO_PAUSE,
    VIDEO_STOP,
    VIDEO_IS_PLAYING,
    VIDEO_GET_CURRENT_TIME,
    VIDEO_SET_CURRENT_TIME,
    VIDEO_ADD_ENDED_CALLBACK,
};

// Only video closures carry a Source reference. The embedded ordinary handle
// continues through the same logical-layer resolver and ownership contract.
typedef struct {
    MWXSceneQuickJSLayerAccessHandle layer;
    uint32_t source_index;
    uint64_t source_incarnation[2];
} MWXSceneQuickJSVideoAccessHandle;

enum TextureAnimationProperty {
    TEXTURE_ANIMATION_FRAME_COUNT,
    TEXTURE_ANIMATION_DURATION,
    TEXTURE_ANIMATION_RATE,
};

enum TextureAnimationFunction {
    TEXTURE_ANIMATION_PLAY,
    TEXTURE_ANIMATION_PAUSE,
    TEXTURE_ANIMATION_STOP,
    TEXTURE_ANIMATION_IS_PLAYING,
    TEXTURE_ANIMATION_GET_FRAME,
    TEXTURE_ANIMATION_SET_FRAME,
    TEXTURE_ANIMATION_JOIN,
};

static MWXSceneQuickJSLayerRecord *video_record_for_handle(
    MWXSceneQuickJSVideoAccessHandle *handle
) {
    MWXSceneQuickJSLayerRecord *record = mwx_scene_quickjs_layer_record_for_handle(
        &handle->layer, MWX_SCENE_QUICKJS_LAYER_OWNER_BOUND);
    MWXSceneQuickJSDomain *domain = handle->layer.domain;
    if (record == NULL || record->video_source_index != handle->source_index ||
        record->video_source_index >= domain->video_observation_count) return NULL;
    const MWXSceneQuickJSVideoObservation *video = &domain->video_observations[record->video_source_index];
    return video->available && memcmp(video->source_incarnation, handle->source_incarnation,
        sizeof(video->source_incarnation)) == 0 ? record : NULL;
}

static size_t media_playback_callback_start(MWXSceneQuickJSOwner *owner) {
    if (owner->media_playback_callback_epoch != owner->domain->callback_epoch) {
        owner->media_playback_callback_epoch = owner->domain->callback_epoch;
        owner->media_playback_callback_start = owner->media_playback_command_count;
    }
    return owner->media_playback_callback_start;
}

static bool append_media_playback_command(
    MWXSceneQuickJSOwner *owner,
    MWXSceneQuickJSLayerRecord *record,
    uint32_t destination,
    uint32_t kind,
    double number_value,
    uint32_t bool_value
) {
    if (owner->value_only) return false;
    const size_t callback_start = media_playback_callback_start(owner);
    if (owner->media_playback_command_count >= MWX_SCENE_QUICKJS_MAX_MEDIA_PLAYBACK_COMMANDS) {
        owner->media_playback_command_overflow = true;
        return false;
    }
    const uint32_t ordinal = (uint32_t)(owner->media_playback_command_count - callback_start);
    owner->media_playback_commands[owner->media_playback_command_count++] =
        (MWXSceneQuickJSMediaPlaybackCommand){
            .kind = kind,
            .destination = destination,
            .layer_id = record->layer_id,
            .number_value = number_value,
            .bool_value = bool_value,
            .ordinal = ordinal,
            .callback_epoch = owner->domain->callback_epoch,
        };
    if (destination == MWX_SCENE_QUICKJS_MEDIA_VIDEO_TEXTURE) {
        memcpy(owner->media_playback_commands[owner->media_playback_command_count - 1].video_source_incarnation,
            owner->domain->video_observations[record->video_source_index].source_incarnation, sizeof(uint64_t) * 2);
    }
    return true;
}

static JSValue media_playback_command_failure(JSContext *context, MWXSceneQuickJSOwner *owner) {
    return owner->value_only
        ? JS_ThrowTypeError(context, "media playback control requires a stateful owner")
        : JS_ThrowInternalError(context, "media playback command buffer exceeded");
}

static JSValue video_get(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)argc; (void)argv;
    MWXSceneQuickJSVideoAccessHandle *handle = opaque;
    MWXSceneQuickJSLayerRecord *record = video_record_for_handle(handle);
    if (record == NULL) return JS_ThrowTypeError(context, "video handle is stale");
    const MWXSceneQuickJSVideoObservation *video =
        &handle->layer.domain->video_observations[record->video_source_index];
    switch ((enum VideoProperty)magic) {
    case VIDEO_DURATION: return JS_NewFloat64(context, video->duration);
    case VIDEO_RATE: return JS_NewFloat64(context, video->rate);
    case VIDEO_LOOP: return JS_NewBool(context, video->loop);
    }
    return JS_UNDEFINED;
}

static JSValue video_set(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value;
    MWXSceneQuickJSVideoAccessHandle *handle = opaque;
    MWXSceneQuickJSLayerRecord *record = video_record_for_handle(handle);
    if (record == NULL || argc != 1)
        return JS_ThrowTypeError(context, "video handle is stale");
    MWXSceneQuickJSOwner *owner = handle->layer.domain->active_owner;
    bool accepted = false;
    if ((enum VideoProperty)magic == VIDEO_RATE) {
        double value = 0;
        if (JS_ToFloat64(context, &value, argv[0]) < 0 || !isfinite(value) ||
            value <= 0 || value > 16)
            return JS_ThrowRangeError(context, "video rate must be finite in (0, 16]");
        accepted = append_media_playback_command(
            owner, record, MWX_SCENE_QUICKJS_MEDIA_VIDEO_TEXTURE,
            MWX_SCENE_QUICKJS_MEDIA_SET_RATE, value, 0
        );
    } else if ((enum VideoProperty)magic == VIDEO_LOOP) {
        int value = JS_ToBool(context, argv[0]);
        if (value < 0) return JS_EXCEPTION;
        accepted = append_media_playback_command(
            owner, record, MWX_SCENE_QUICKJS_MEDIA_VIDEO_TEXTURE,
            MWX_SCENE_QUICKJS_MEDIA_SET_LOOP, 0,
            value != 0 ? 1 : 0
        );
    } else {
        return JS_ThrowTypeError(context, "video duration is read-only");
    }
    return accepted ? JS_UNDEFINED : media_playback_command_failure(context, owner);
}

static JSValue video_call(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value;
    MWXSceneQuickJSVideoAccessHandle *handle = opaque;
    MWXSceneQuickJSLayerRecord *record = video_record_for_handle(handle);
    if (record == NULL) return JS_ThrowTypeError(context, "video handle is stale");
    const MWXSceneQuickJSVideoObservation *video =
        &handle->layer.domain->video_observations[record->video_source_index];
    MWXSceneQuickJSOwner *owner = handle->layer.domain->active_owner;
    switch ((enum VideoFunction)magic) {
    case VIDEO_IS_PLAYING:
        if (argc != 0) return JS_ThrowTypeError(context, "isPlaying expects no arguments");
        return JS_NewBool(context, video->is_playing);
    case VIDEO_GET_CURRENT_TIME:
        if (argc != 0)
            return JS_ThrowTypeError(context, "getCurrentTime expects no arguments");
        return JS_NewFloat64(context, video->current_time);
    case VIDEO_SET_CURRENT_TIME: {
        double value = 0;
        if (argc != 1 || JS_ToFloat64(context, &value, argv[0]) < 0 ||
            !isfinite(value) || value < 0 ||
            (video->duration > 0 && value > video->duration))
            return JS_ThrowRangeError(
                context, "setCurrentTime expects a bounded finite time"
            );
        if (!append_media_playback_command(
                owner, record, MWX_SCENE_QUICKJS_MEDIA_VIDEO_TEXTURE,
                MWX_SCENE_QUICKJS_MEDIA_SET_CURRENT_TIME,
                value, 0
            )) return media_playback_command_failure(context, owner);
        return JS_UNDEFINED;
    }
    case VIDEO_ADD_ENDED_CALLBACK: {
        if (argc != 1 || !JS_IsFunction(context, argv[0]))
            return JS_ThrowTypeError(context, "addEndedCallback expects a function");
        if (owner->video_ended_callback_count >=
            MWX_SCENE_QUICKJS_MAX_VIDEO_ENDED_CALLBACKS)
            return JS_ThrowInternalError(context, "video callback buffer exceeded");
        MWXSceneQuickJSVideoEndedCallbackRecord *callback =
            &owner->video_ended_callbacks[owner->video_ended_callback_count++];
        *callback = (MWXSceneQuickJSVideoEndedCallbackRecord){
            .layer_id = record->layer_id,
            .layer_index = handle->layer.layer_index,
            .video_source_index = record->video_source_index,
            .source_incarnation = {video->source_incarnation[0], video->source_incarnation[1]},
            .delivered_generation = video->ended_generation,
            .callback = JS_DupValue(context, argv[0]),
            .active = true,
        };
        return JS_UNDEFINED;
    }
    case VIDEO_PLAY:
    case VIDEO_PAUSE:
    case VIDEO_STOP: {
        if (argc != 0) return JS_ThrowTypeError(context, "video command expects no arguments");
        const uint32_t kind = (enum VideoFunction)magic == VIDEO_PLAY
            ? MWX_SCENE_QUICKJS_MEDIA_PLAY
            : ((enum VideoFunction)magic == VIDEO_PAUSE
                ? MWX_SCENE_QUICKJS_MEDIA_PAUSE
                : MWX_SCENE_QUICKJS_MEDIA_STOP);
        if (!append_media_playback_command(owner, record,
                MWX_SCENE_QUICKJS_MEDIA_VIDEO_TEXTURE, kind, 0, 0))
            return media_playback_command_failure(context, owner);
        return JS_UNDEFINED;
    }
    }
    return JS_UNDEFINED;
}

static void free_layer_resource_handle(void *opaque) { free(opaque); }

static void *copy_layer_resource_handle(const void *identity, size_t size) {
    void *copy = malloc(size);
    if (copy != NULL) memcpy(copy, identity, size);
    return copy;
}

static JSValue make_video_handle(
    JSContext *context, MWXSceneQuickJSOwner *owner, uint32_t layer_index
) {
    MWXSceneQuickJSVideoAccessHandle identity = {
        .layer = {.domain = owner->domain, .owner_identity = owner->identity,
            .layer_index = layer_index, .expected_layer_id = owner->domain->layers[layer_index].layer_id,
            .persistent = true},
        .source_index = owner->domain->layers[layer_index].video_source_index,
    };
    memcpy(identity.source_incarnation,
        owner->domain->video_observations[identity.source_index].source_incarnation,
        sizeof(identity.source_incarnation));
    JSValue video = JS_NewObject(context);
    if (JS_IsException(video)) return video;
    const struct {
        const char *name; enum VideoProperty property; bool writable;
    } properties[] = {
        {"duration", VIDEO_DURATION, false},
        {"rate", VIDEO_RATE, true},
        {"loop", VIDEO_LOOP, true},
    };
    for (size_t index = 0; index < sizeof(properties) / sizeof(properties[0]); ++index) {
        MWXSceneQuickJSVideoAccessHandle *getter_handle = copy_layer_resource_handle(&identity, sizeof(identity));
        MWXSceneQuickJSVideoAccessHandle *setter_handle = properties[index].writable
            ? copy_layer_resource_handle(&identity, sizeof(identity)) : NULL;
        if (getter_handle == NULL ||
            (properties[index].writable && setter_handle == NULL)) {
            free(getter_handle); free(setter_handle); JS_FreeValue(context, video);
            return JS_EXCEPTION;
        }
        JSValue getter = JS_NewCClosure(
            context, video_get, properties[index].name, free_layer_resource_handle,
            0, properties[index].property, getter_handle
        );
        JSValue setter = properties[index].writable ? JS_NewCClosure(
            context, video_set, properties[index].name, free_layer_resource_handle,
            1, properties[index].property, setter_handle
        ) : JS_UNDEFINED;
        JSAtom atom = JS_NewAtom(context, properties[index].name);
        int result = JS_DefinePropertyGetSet(
            context, video, atom, getter, setter, JS_PROP_ENUMERABLE
        );
        JS_FreeAtom(context, atom);
        if (result < 0) { JS_FreeValue(context, video); return JS_EXCEPTION; }
    }
    const struct { const char *name; enum VideoFunction function; int argc; } functions[] = {
        {"play", VIDEO_PLAY, 0}, {"pause", VIDEO_PAUSE, 0},
        {"stop", VIDEO_STOP, 0}, {"isPlaying", VIDEO_IS_PLAYING, 0},
        {"getCurrentTime", VIDEO_GET_CURRENT_TIME, 0},
        {"setCurrentTime", VIDEO_SET_CURRENT_TIME, 1},
        {"addEndedCallback", VIDEO_ADD_ENDED_CALLBACK, 1},
    };
    for (size_t index = 0; index < sizeof(functions) / sizeof(functions[0]); ++index) {
        MWXSceneQuickJSVideoAccessHandle *function_handle = copy_layer_resource_handle(&identity, sizeof(identity));
        if (function_handle == NULL) { JS_FreeValue(context, video); return JS_EXCEPTION; }
        JSValue function = JS_NewCClosure(
            context, video_call, functions[index].name, free_layer_resource_handle,
            functions[index].argc, functions[index].function, function_handle
        );
        if (JS_IsException(function) || JS_DefinePropertyValueStr(
                context, video, functions[index].name, function,
                JS_PROP_ENUMERABLE
            ) < 0) { JS_FreeValue(context, video); return JS_EXCEPTION; }
    }
    return video;
}

static JSValue get_video_texture(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)argv; (void)magic;
    MWXSceneQuickJSLayerAccessHandle *handle = opaque;
    MWXSceneQuickJSLayerRecord *record = mwx_scene_quickjs_layer_record_for_handle(handle, MWX_SCENE_QUICKJS_LAYER_OWNER_BOUND);
    if (record == NULL || argc != 0)
        return JS_ThrowTypeError(context, "getVideoTexture unavailable");
    if (record->video_source_index >= handle->domain->video_observation_count ||
        !handle->domain->video_observations[record->video_source_index].available) return JS_UNDEFINED;
    uint32_t index = handle->owner_target
        ? handle->domain->active_owner->target_layer_index
        : handle->layer_index;
    return make_video_handle(
        context, handle->domain->active_owner, index
    );
}

bool mwx_scene_quickjs_layer_define_get_video_texture(
    JSContext *context, JSValue layer, MWXSceneQuickJSOwner *owner,
    uint32_t index, bool owner_target, bool persistent
) {
    MWXSceneQuickJSLayerAccessHandle *handle = calloc(1, sizeof(*handle));
    if (handle == NULL) { JS_ThrowOutOfMemory(context); return false; }
    *handle = (MWXSceneQuickJSLayerAccessHandle){
        .domain = owner->domain, .owner_identity = owner->identity,
        .layer_index = index, .callback_epoch = owner->domain->callback_epoch,
        .expected_layer_id = owner_target ? 0 : owner->domain->layers[index].layer_id,
        .owner_target = owner_target, .persistent = persistent,
    };
    JSValue function = mwx_scene_quickjs_layer_access_closure(
        context, get_video_texture, "getVideoTexture", 0, 0, handle
    );
    return !JS_IsException(function) && JS_DefinePropertyValueStr(
        context, layer, "getVideoTexture", function, JS_PROP_ENUMERABLE
    ) >= 0;
}

// play/pause/stop and isPlaying share the ordinary layer-handle identity checks.
static JSValue layer_playback_call(JSContext *context, JSValueConst this_value,
    int argc, JSValueConst *argv, int magic, void *opaque) {
    (void)this_value;
    MWXSceneQuickJSDomain *domain = JS_GetContextOpaque(context);
    if (domain != NULL && domain->text_clone_depth != 0 && magic != 3) {
        // Reject before handle/argument lookup or any Swift preview/reservation.
        // During module evaluation the child has no provisional parent yet.
        MWXSceneQuickJSOwner *nested = domain->callback_active
            ? domain->active_owner : domain->module_owner;
        if (nested != NULL) {
            nested->text_clone_failed = true;
            nested->particle_playback_command_overflow = true;
            if (nested->provisional_text_creator != NULL)
                nested->provisional_text_creator->text_clone_failed = true;
        }
        return JS_ThrowTypeError(context, "prepared text init particle commands are unavailable");
    }
    MWXSceneQuickJSLayerAccessHandle *handle = opaque;
    MWXSceneQuickJSLayerRecord *record = mwx_scene_quickjs_layer_record_for_handle(handle, MWX_SCENE_QUICKJS_LAYER_OWNER_BOUND);
    if ((magic == 4 ? argc != 1 : argc != 0) || record == NULL)
        return JS_ThrowTypeError(context, "layer playback unavailable or unsupported arguments");
    MWXSceneQuickJSOwner *owner = handle->domain->active_owner;
    if (magic != 4 && record->sound_available) {
        if (magic == 3) {
            bool playing = record->sound_is_playing;
            for (size_t index = media_playback_callback_start(owner);
                 index < owner->media_playback_command_count; ++index) {
                const MWXSceneQuickJSMediaPlaybackCommand *command = &owner->media_playback_commands[index];
                if (command->destination == MWX_SCENE_QUICKJS_MEDIA_SOUND_LAYER &&
                    command->layer_id == record->layer_id)
                    playing = command->kind == MWX_SCENE_QUICKJS_MEDIA_PLAY;
            }
            return JS_NewBool(context, playing);
        }
        uint32_t kind = magic == 0 ? MWX_SCENE_QUICKJS_MEDIA_PLAY
            : (magic == 1 ? MWX_SCENE_QUICKJS_MEDIA_PAUSE : MWX_SCENE_QUICKJS_MEDIA_STOP);
        if (!append_media_playback_command(owner, record,
                MWX_SCENE_QUICKJS_MEDIA_SOUND_LAYER, kind, 0, 0))
            return media_playback_command_failure(context, owner);
        return JS_UNDEFINED;
    }
    if (!record->particle_playback.available)
        return JS_ThrowTypeError(context, "particle playback unavailable or unsupported arguments");
    uint32_t count = 0;
    if (magic == 4) {
        double value;
        if (!JS_IsNumber(argv[0]) || JS_ToFloat64(context, &value, argv[0]) < 0 ||
            !isfinite(value) || value < 0 || value > 1024 || floor(value) != value)
            return JS_ThrowTypeError(context, "emitParticles requires an explicit integer from 0 to 1024");
        count = (uint32_t)value;
    }
    MWXSceneQuickJSParticlePlaybackState staged = record->particle_playback;
    for (size_t index = 0; index < owner->particle_playback_command_count; ++index) {
        const MWXSceneQuickJSParticlePlaybackCommand *command = &owner->particle_playback_commands[index];
        if (command->layer_id != record->layer_id || command->callback_epoch != owner->domain->callback_epoch) continue;
        if (command->action == 4) { staged = command->verified_projection; continue; }
        staged.intent = command->action;
        if (command->action == 2) { staged.live = 0; staged.emission_pending = staged.rearm_has_work; }
        if (command->action == 0 && !staged.emission_pending)
            staged.emission_pending = staged.rearm_has_work;
    }
    if (magic == 3) {
        if (owner->domain->particle_frame_active &&
            mwx_scene_quickjs_domain_particle_charge(owner->domain, 1, 0) != MWX_SCENE_QUICKJS_OK) {
            owner->particle_playback_command_overflow = true;
            return JS_ThrowInternalError(context, "particle query native budget exceeded");
        }
        return JS_NewBool(context, staged.live || (staged.intent == 0 && staged.emission_pending));
    }
    if (owner->particle_playback_command_count >= MWX_SCENE_QUICKJS_MAX_PARTICLE_PLAYBACK_COMMANDS) {
        owner->particle_playback_command_overflow = true;
        return JS_ThrowInternalError(context, "particle playback command budget exceeded");
    }
    uint32_t ordinal = 0;
    for (size_t index = owner->particle_playback_command_count; index > 0; --index) {
        if (owner->particle_playback_commands[index - 1].callback_epoch != owner->domain->callback_epoch) break;
        ordinal += 1;
    }
    MWXSceneQuickJSParticlePlaybackCommand command = {
        .layer_id = record->layer_id, .action = (uint32_t)magic, .count = count,
        .ordinal = ordinal, .callback_epoch = owner->domain->callback_epoch
    };
    if (magic == 4) {
        if (owner->domain->particle_emission == NULL)
            return JS_ThrowTypeError(context, "particle emission unavailable");
        MWXSceneQuickJSResult result = owner->domain->particle_emission(
            owner->domain->particle_emission_opaque, owner, &command, &command.verified_projection);
        if (result != MWX_SCENE_QUICKJS_OK) {
            if (result != MWX_SCENE_QUICKJS_INVALID_ARGUMENT)
                owner->particle_playback_command_overflow = true;
            return JS_ThrowInternalError(context, "particle emission rejected (%d)", (int)result);
        }
    }
    owner->particle_playback_commands[owner->particle_playback_command_count++] = command;
    return JS_UNDEFINED;
}

bool mwx_scene_quickjs_layer_define_layer_playback(JSContext *context, JSValue layer,
    MWXSceneQuickJSOwner *owner, uint32_t index, bool owner_target, bool persistent) {
    const char *names[] = {"play", "pause", "stop", "isPlaying", "emitParticles"};
    for (int action = 0; action < 5; ++action) {
        MWXSceneQuickJSLayerAccessHandle *handle = calloc(1, sizeof(*handle));
        if (handle == NULL) { JS_ThrowOutOfMemory(context); return false; }
        *handle = (MWXSceneQuickJSLayerAccessHandle){ .domain = owner->domain,
            .owner_identity = owner->identity, .layer_index = index,
            .expected_layer_id = owner_target ? 0 : owner->domain->layers[index].layer_id,
            .callback_epoch = owner->domain->callback_epoch,
            .owner_target = owner_target, .persistent = persistent };
        JSValue function = mwx_scene_quickjs_layer_access_closure(context, layer_playback_call,
            names[action], 0, action, handle);
        if (JS_IsException(function) || JS_DefinePropertyValueStr(context, layer,
            names[action], function, JS_PROP_ENUMERABLE) < 0) return false;
    }
    return true;
}

static MWXSceneQuickJSLayerRecord *texture_animation_record_for_handle(
    MWXSceneQuickJSLayerAccessHandle *handle
) {
    MWXSceneQuickJSLayerRecord *record = mwx_scene_quickjs_layer_record_for_handle(
        handle, MWX_SCENE_QUICKJS_LAYER_OWNER_BOUND);
    return record != NULL && record->texture_animation_available ? record : NULL;
}

static bool append_texture_animation_command(
    MWXSceneQuickJSOwner *owner,
    MWXSceneQuickJSLayerRecord *record,
    uint32_t kind,
    double number_value
) {
    if (owner->texture_animation_command_count >=
        MWX_SCENE_QUICKJS_MAX_TEXTURE_ANIMATION_COMMANDS) {
        owner->texture_animation_command_overflow = true;
        return false;
    }
    owner->texture_animation_commands[
        owner->texture_animation_command_count++
    ] = (MWXSceneQuickJSTextureAnimationCommand){
        .kind = kind,
        .layer_id = record->layer_id,
        .number_value = number_value,
    };
    return true;
}

static void texture_animation_staged_state(
    const MWXSceneQuickJSOwner *owner,
    const MWXSceneQuickJSLayerRecord *record,
    double *rate,
    double *frame,
    bool *is_playing
) {
    *rate = record->texture_animation_rate;
    *frame = record->texture_animation_current_frame;
    *is_playing = record->texture_animation_is_playing;
    for (size_t index = 0;
         index < owner->texture_animation_command_count; ++index) {
        const MWXSceneQuickJSTextureAnimationCommand *command =
            &owner->texture_animation_commands[index];
        if (command->layer_id != record->layer_id) continue;
        switch (command->kind) {
        case MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_PLAY:
            *is_playing = true;
            break;
        case MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_PAUSE:
            *is_playing = false;
            break;
        case MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_STOP:
            *frame = 0;
            *is_playing = false;
            break;
        case MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_SET_FRAME:
            *frame = command->number_value;
            break;
        case MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_SET_RATE:
            *rate = command->number_value;
            break;
        case MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_JOIN:
            *rate = record->texture_animation_shared_rate;
            *frame = record->texture_animation_shared_current_frame;
            *is_playing = record->texture_animation_shared_is_playing;
            break;
        default:
            break;
        }
    }
}

static JSValue texture_animation_get(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)argc; (void)argv;
    MWXSceneQuickJSLayerAccessHandle *handle = opaque;
    MWXSceneQuickJSLayerRecord *record =
        texture_animation_record_for_handle(handle);
    if (record == NULL)
        return JS_ThrowTypeError(context, "texture animation handle is stale");
    if ((enum TextureAnimationProperty)magic ==
        TEXTURE_ANIMATION_FRAME_COUNT)
        return JS_NewUint32(context, record->texture_animation_frame_count);
    if ((enum TextureAnimationProperty)magic == TEXTURE_ANIMATION_DURATION)
        return JS_NewFloat64(context, record->texture_animation_duration);
    double rate = 0, frame = 0;
    bool is_playing = false;
    texture_animation_staged_state(
        handle->domain->active_owner, record, &rate, &frame, &is_playing
    );
    return JS_NewFloat64(context, rate);
}

static JSValue texture_animation_set(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value;
    MWXSceneQuickJSLayerAccessHandle *handle = opaque;
    MWXSceneQuickJSLayerRecord *record =
        texture_animation_record_for_handle(handle);
    if (record == NULL || argc != 1)
        return JS_ThrowTypeError(context, "texture animation handle is stale");
    if ((enum TextureAnimationProperty)magic != TEXTURE_ANIMATION_RATE)
        return JS_ThrowTypeError(
            context, "texture animation property is read-only"
        );
    double value = 0;
    if (JS_ToFloat64(context, &value, argv[0]) < 0 || !isfinite(value) ||
        fabs(value) > 16)
        return JS_ThrowRangeError(
            context, "texture animation rate must be finite in [-16, 16]"
        );
    return append_texture_animation_command(
        handle->domain->active_owner, record,
        MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_SET_RATE, value
    ) ? JS_UNDEFINED : JS_ThrowInternalError(
        context, "texture animation command buffer exceeded"
    );
}

static JSValue texture_animation_call(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value;
    MWXSceneQuickJSLayerAccessHandle *handle = opaque;
    MWXSceneQuickJSLayerRecord *record =
        texture_animation_record_for_handle(handle);
    if (record == NULL)
        return JS_ThrowTypeError(context, "texture animation handle is stale");
    MWXSceneQuickJSOwner *owner = handle->domain->active_owner;
    double rate = 0, frame = 0;
    bool is_playing = false;
    texture_animation_staged_state(
        owner, record, &rate, &frame, &is_playing
    );
    switch ((enum TextureAnimationFunction)magic) {
    case TEXTURE_ANIMATION_IS_PLAYING:
        if (argc != 0)
            return JS_ThrowTypeError(context, "isPlaying expects no arguments");
        return JS_NewBool(context, is_playing);
    case TEXTURE_ANIMATION_GET_FRAME:
        if (argc != 0)
            return JS_ThrowTypeError(context, "getFrame expects no arguments");
        return JS_NewFloat64(context, frame);
    case TEXTURE_ANIMATION_SET_FRAME: {
        double value = 0;
        if (argc != 1 || JS_ToFloat64(context, &value, argv[0]) < 0 ||
            !isfinite(value) || value < 0 ||
            value >= record->texture_animation_frame_count)
            return JS_ThrowRangeError(
                context, "setFrame expects a frame in [0, frameCount)"
            );
        if (!append_texture_animation_command(
                owner, record,
                MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_SET_FRAME, floor(value)))
            return JS_ThrowInternalError(
                context, "texture animation command buffer exceeded"
            );
        return JS_UNDEFINED;
    }
    case TEXTURE_ANIMATION_PLAY:
    case TEXTURE_ANIMATION_PAUSE:
    case TEXTURE_ANIMATION_STOP:
    case TEXTURE_ANIMATION_JOIN: {
        if (argc != 0)
            return JS_ThrowTypeError(
                context, "texture animation command expects no arguments"
            );
        const uint32_t kind =
            (enum TextureAnimationFunction)magic == TEXTURE_ANIMATION_PLAY
                ? MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_PLAY
            : (enum TextureAnimationFunction)magic == TEXTURE_ANIMATION_PAUSE
                ? MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_PAUSE
            : (enum TextureAnimationFunction)magic == TEXTURE_ANIMATION_STOP
                ? MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_STOP
                : MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_JOIN;
        if (!append_texture_animation_command(owner, record, kind, 0))
            return JS_ThrowInternalError(
                context, "texture animation command buffer exceeded"
            );
        return JS_UNDEFINED;
    }
    }
    return JS_UNDEFINED;
}

static JSValue make_texture_animation_handle(
    JSContext *context, MWXSceneQuickJSOwner *owner, uint32_t layer_index
) {
    MWXSceneQuickJSLayerAccessHandle identity = {
        .domain = owner->domain,
        .owner_identity = owner->identity,
        .layer_index = layer_index,
        .expected_layer_id = owner->domain->layers[layer_index].layer_id,
        .persistent = true,
    };
    JSValue animation = JS_NewObject(context);
    if (JS_IsException(animation)) return animation;
    const struct {
        const char *name; enum TextureAnimationProperty property; bool writable;
    } properties[] = {
        {"frameCount", TEXTURE_ANIMATION_FRAME_COUNT, false},
        {"duration", TEXTURE_ANIMATION_DURATION, false},
        {"rate", TEXTURE_ANIMATION_RATE, true},
    };
    for (size_t index = 0;
         index < sizeof(properties) / sizeof(properties[0]); ++index) {
        MWXSceneQuickJSLayerAccessHandle *getter = copy_layer_resource_handle(&identity, sizeof(identity));
        MWXSceneQuickJSLayerAccessHandle *setter = properties[index].writable
            ? copy_layer_resource_handle(&identity, sizeof(identity)) : NULL;
        if (getter == NULL || (properties[index].writable && setter == NULL)) {
            free(getter); free(setter); JS_FreeValue(context, animation);
            return JS_EXCEPTION;
        }
        JSValue getter_value = JS_NewCClosure(
            context, texture_animation_get, properties[index].name,
            free_layer_resource_handle, 0, properties[index].property, getter
        );
        JSValue setter_value = properties[index].writable ? JS_NewCClosure(
            context, texture_animation_set, properties[index].name,
            free_layer_resource_handle, 1, properties[index].property, setter
        ) : JS_UNDEFINED;
        JSAtom atom = JS_NewAtom(context, properties[index].name);
        int result = JS_DefinePropertyGetSet(
            context, animation, atom, getter_value, setter_value,
            JS_PROP_ENUMERABLE
        );
        JS_FreeAtom(context, atom);
        if (result < 0) {
            JS_FreeValue(context, animation);
            return JS_EXCEPTION;
        }
    }
    const struct {
        const char *name; enum TextureAnimationFunction function; int argc;
    } functions[] = {
        {"play", TEXTURE_ANIMATION_PLAY, 0},
        {"pause", TEXTURE_ANIMATION_PAUSE, 0},
        {"stop", TEXTURE_ANIMATION_STOP, 0},
        {"isPlaying", TEXTURE_ANIMATION_IS_PLAYING, 0},
        {"getFrame", TEXTURE_ANIMATION_GET_FRAME, 0},
        {"setFrame", TEXTURE_ANIMATION_SET_FRAME, 1},
        {"join", TEXTURE_ANIMATION_JOIN, 0},
    };
    for (size_t index = 0;
         index < sizeof(functions) / sizeof(functions[0]); ++index) {
        MWXSceneQuickJSLayerAccessHandle *handle = copy_layer_resource_handle(&identity, sizeof(identity));
        if (handle == NULL) {
            JS_FreeValue(context, animation);
            return JS_EXCEPTION;
        }
        JSValue function = JS_NewCClosure(
            context, texture_animation_call, functions[index].name,
            free_layer_resource_handle, functions[index].argc,
            functions[index].function, handle
        );
        if (JS_IsException(function) || JS_DefinePropertyValueStr(
                context, animation, functions[index].name, function,
                JS_PROP_ENUMERABLE) < 0) {
            JS_FreeValue(context, animation);
            return JS_EXCEPTION;
        }
    }
    return animation;
}

static JSValue get_texture_animation(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)argv; (void)magic;
    MWXSceneQuickJSLayerAccessHandle *handle = opaque;
    MWXSceneQuickJSLayerRecord *record = mwx_scene_quickjs_layer_record_for_handle(handle, MWX_SCENE_QUICKJS_LAYER_OWNER_BOUND);
    if (record == NULL || argc != 0)
        return JS_ThrowTypeError(context, "getTextureAnimation unavailable");
    if (!record->texture_animation_available) return JS_UNDEFINED;
    uint32_t index = handle->owner_target
        ? handle->domain->active_owner->target_layer_index
        : handle->layer_index;
    return make_texture_animation_handle(
        context, handle->domain->active_owner, index
    );
}

bool mwx_scene_quickjs_layer_define_get_texture_animation(
    JSContext *context, JSValue layer, MWXSceneQuickJSOwner *owner,
    uint32_t index, bool owner_target, bool persistent
) {
    MWXSceneQuickJSLayerAccessHandle *handle = calloc(1, sizeof(*handle));
    if (handle == NULL) { JS_ThrowOutOfMemory(context); return false; }
    *handle = (MWXSceneQuickJSLayerAccessHandle){
        .domain = owner->domain, .owner_identity = owner->identity,
        .layer_index = index, .callback_epoch = owner->domain->callback_epoch,
        .expected_layer_id = owner_target ? 0 : owner->domain->layers[index].layer_id,
        .owner_target = owner_target, .persistent = persistent,
    };
    JSValue function = mwx_scene_quickjs_layer_access_closure(
        context, get_texture_animation, "getTextureAnimation",
        0, 0, handle
    );
    return !JS_IsException(function) && JS_DefinePropertyValueStr(
        context, layer, "getTextureAnimation", function, JS_PROP_ENUMERABLE
    ) >= 0;
}

size_t mwx_scene_quickjs_owner_media_playback_command_count(
    const MWXSceneQuickJSOwner *owner
) {
    // Catching the JS exception cannot turn a truncated native journal into
    // an accepted transaction. Match the existing particle admission ABI.
    if (owner != NULL && owner->media_playback_command_overflow)
        return MWX_SCENE_QUICKJS_MAX_MEDIA_PLAYBACK_COMMANDS + 1;
    return owner == NULL ? 0 : owner->media_playback_command_count;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_media_playback_command_at(
    const MWXSceneQuickJSOwner *owner,
    size_t requested,
    MWXSceneQuickJSMediaPlaybackCommand *command,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner != NULL && owner->media_playback_command_overflow) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "media playback command buffer exceeded"
        );
        return MWX_SCENE_QUICKJS_MUTATION_OVERFLOW;
    }
    if (owner == NULL || command == NULL ||
        requested >= owner->media_playback_command_count ||
        requested >= MWX_SCENE_QUICKJS_MAX_MEDIA_PLAYBACK_COMMANDS) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid media playback command index"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    *command = owner->media_playback_commands[requested];
    return MWX_SCENE_QUICKJS_OK;
}

size_t mwx_scene_quickjs_owner_texture_animation_command_count(
    const MWXSceneQuickJSOwner *owner
) {
    return owner == NULL ? 0 : owner->texture_animation_command_count;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_texture_animation_command_at(
    const MWXSceneQuickJSOwner *owner,
    size_t requested,
    MWXSceneQuickJSTextureAnimationCommand *command,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner == NULL || command == NULL ||
        requested >= owner->texture_animation_command_count ||
        requested >= MWX_SCENE_QUICKJS_MAX_TEXTURE_ANIMATION_COMMANDS) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "invalid texture animation command index"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    *command = owner->texture_animation_commands[requested];
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_dispatch_video_ended_callbacks(
    MWXSceneQuickJSOwner *owner, char *diagnostic, size_t diagnostic_capacity
) {
    if (!mwx_scene_quickjs_layer_callback_owns(owner)) return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    JSContext *context = owner->domain->context;
    for (size_t index = 0; index < owner->video_ended_callback_count; ++index) {
        MWXSceneQuickJSVideoEndedCallbackRecord *callback =
            &owner->video_ended_callbacks[index];
        if (!callback->active) continue;
        MWXSceneQuickJSVideoAccessHandle identity = {
            .layer = {.domain = owner->domain, .owner_identity = owner->identity,
                .layer_index = callback->layer_index, .expected_layer_id = callback->layer_id, .persistent = true},
            .source_index = callback->video_source_index,
            .source_incarnation = {callback->source_incarnation[0], callback->source_incarnation[1]},
        };
        MWXSceneQuickJSLayerRecord *record = video_record_for_handle(&identity);
        if (record == NULL) continue;
        const uint64_t ended_generation = owner->domain->video_observations[
            record->video_source_index].ended_generation;
        if (ended_generation <= callback->delivered_generation) continue;
        mwx_scene_quickjs_begin_callback(owner);
        JSValue result = JS_Call(
            context, callback->callback, owner->module, 0, NULL
        );
        MWXSceneQuickJSResult outcome;
        if (JS_IsException(result)) {
            mwx_scene_quickjs_discard_jobs(owner);
            outcome = mwx_scene_quickjs_exception_result(
                owner->domain, diagnostic, diagnostic_capacity
            );
        } else {
            outcome = mwx_scene_quickjs_drain_jobs(
                owner, diagnostic, diagnostic_capacity
            );
        }
        JS_FreeValue(context, result);
        if (outcome != MWX_SCENE_QUICKJS_OK) {
            return owner->material_function_overflow || owner->animation_command_overflow ||
                owner->media_playback_command_overflow || owner->texture_animation_command_overflow ||
                owner->particle_playback_command_overflow || owner->storage_mutation_overflow
                ? MWX_SCENE_QUICKJS_MUTATION_OVERFLOW : outcome;
        }
        callback->delivered_generation = ended_generation;
    }
    return MWX_SCENE_QUICKJS_OK;
}

void mwx_scene_quickjs_clear_video_ended_callbacks(
    MWXSceneQuickJSOwner *owner
) {
    if (owner == NULL || owner->domain == NULL ||
        owner->domain->context == NULL) return;
    for (size_t index = 0; index < owner->video_ended_callback_count; ++index) {
        MWXSceneQuickJSVideoEndedCallbackRecord *callback =
            &owner->video_ended_callbacks[index];
        if (callback->active) {
            JS_FreeValue(owner->domain->context, callback->callback);
            callback->active = false;
        }
    }
    owner->video_ended_callback_count = owner->committed_video_ended_callback_count = 0;
}

// Callback roots join the existing owner journal. Failed registrations never
// survive admission; accepted short-lived carriers release their roots here.
void mwx_scene_quickjs_finish_video_ended_callbacks(MWXSceneQuickJSOwner *owner, bool committing) {
    if (owner == NULL || owner->domain == NULL) return;
    if (!committing) {
        while (owner->video_ended_callback_count > owner->committed_video_ended_callback_count) {
            MWXSceneQuickJSVideoEndedCallbackRecord *callback =
                &owner->video_ended_callbacks[--owner->video_ended_callback_count];
            JS_FreeValue(owner->domain->context, callback->callback);
            *callback = (MWXSceneQuickJSVideoEndedCallbackRecord){.callback = JS_UNDEFINED};
        }
        return;
    }
    const size_t previous_count = owner->video_ended_callback_count;
    size_t kept = 0;
    for (size_t index = 0; index < owner->video_ended_callback_count; ++index) {
        MWXSceneQuickJSVideoEndedCallbackRecord callback = owner->video_ended_callbacks[index];
        const MWXSceneQuickJSLayerRecord *record = callback.layer_index < owner->domain->layer_count
            ? &owner->domain->layers[callback.layer_index] : NULL;
        const MWXSceneQuickJSVideoObservation *video = callback.video_source_index < owner->domain->video_observation_count
            ? &owner->domain->video_observations[callback.video_source_index] : NULL;
        // A peer's provisional authored edit cannot retire this registration.
        const bool retired = record == NULL || !record->configured || record->layer_id != callback.layer_id ||
            video == NULL || !video->available || record->video_source_index != callback.video_source_index ||
            memcmp(video->source_incarnation, callback.source_incarnation, sizeof(callback.source_incarnation)) != 0 ||
            (record->dynamic && record->owner_identity == owner->identity && record->destroyed);
        if (retired) JS_FreeValue(owner->domain->context, callback.callback);
        else owner->video_ended_callbacks[kept++] = callback;
    }
    for (size_t index = kept; index < previous_count; ++index)
        owner->video_ended_callbacks[index] = (MWXSceneQuickJSVideoEndedCallbackRecord){.callback = JS_UNDEFINED};
    owner->video_ended_callback_count = owner->committed_video_ended_callback_count = kept;
}
