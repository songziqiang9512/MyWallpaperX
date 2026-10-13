#include "SceneScriptQuickJSFixture.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

int mwx_fixture_media_thumbnail(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    int has_thumbnail,
    MWXSceneQuickJSResult expected,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
    };
    MWXSceneQuickJSMediaThumbnailEvent event = {
        .has_thumbnail = has_thumbnail ? 1 : 0,
    };
    MWXSceneQuickJSResult actual =
        mwx_scene_quickjs_owner_dispatch_media_thumbnail(
            owner, generation, &event, &frame, "{}", 2,
            diagnostic, sizeof(diagnostic)
        );
    return mwx_fixture_check(actual == expected, label, diagnostic);
}


int mwx_fixture_media_playback(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    uint32_t state,
    MWXSceneQuickJSResult expected,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
    };
    MWXSceneQuickJSMediaPlaybackEvent event = {.state = state};
    MWXSceneQuickJSResult actual =
        mwx_scene_quickjs_owner_dispatch_media_playback(
            owner, generation, &event, &frame, "{}", 2,
            diagnostic, sizeof(diagnostic)
        );
    return mwx_fixture_check(actual == expected, label, diagnostic);
}


int mwx_fixture_media_properties(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    const char *title,
    const char *artist,
    MWXSceneQuickJSResult expected,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
    };
    MWXSceneQuickJSMediaPropertiesEvent event = {
        .title = title,
        .title_length = strlen(title),
        .artist = artist,
        .artist_length = strlen(artist),
    };
    MWXSceneQuickJSResult actual =
        mwx_scene_quickjs_owner_dispatch_media_properties(
            owner, generation, &event, &frame, "{}", 2,
            diagnostic, sizeof(diagnostic)
        );
    return mwx_fixture_check(actual == expected, label, diagnostic);
}


int mwx_fixture_media_timeline(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    double position,
    double duration,
    MWXSceneQuickJSResult expected,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
    };
    MWXSceneQuickJSMediaTimelineEvent event = {
        .position = position,
        .duration = duration,
    };
    MWXSceneQuickJSResult actual =
        mwx_scene_quickjs_owner_dispatch_media_timeline(
            owner, generation, &event, &frame, "{}", 2,
            diagnostic, sizeof(diagnostic)
        );
    return mwx_fixture_check(actual == expected, label, diagnostic);
}


int mwx_fixture_user_properties(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    const char *changed,
    const char *script_properties,
    const char *all_properties,
    MWXSceneQuickJSResult expected,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
    };
    MWXSceneQuickJSResult actual =
        mwx_scene_quickjs_owner_dispatch_user_properties(
            owner, generation,
            changed, strlen(changed),
            script_properties, strlen(script_properties),
            &frame,
            all_properties, strlen(all_properties),
            diagnostic, sizeof(diagnostic)
        );
    return mwx_fixture_check(actual == expected, label, diagnostic);
}


int mwx_fixture_cursor_event(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    MWXSceneQuickJSCursorEventKind kind,
    MWXSceneQuickJSResult expected,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
    };
    MWXSceneQuickJSCursorEvent event = {
        .world_x = 10,
        .world_y = 20,
        .world_z = 0,
        .local_x = 0.5,
        .local_y = 0.25,
        .local_z = 0,
    };
    const char *properties = "{\"enabled\":true}";
    MWXSceneQuickJSResult actual = mwx_scene_quickjs_owner_dispatch_cursor(
        owner, generation, kind, &event, &frame,
        "", 0,
        properties, strlen(properties),
        diagnostic, sizeof(diagnostic)
    );
    return mwx_fixture_check(actual == expected, label, diagnostic);
}


int mwx_fixture_refresh_audio(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    uint32_t resolution,
    const float *left,
    const float *right,
    MWXSceneQuickJSResult expected,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSResult actual =
        mwx_scene_quickjs_owner_refresh_audio_resolution(
            owner, generation, resolution, left, right, resolution,
            diagnostic, sizeof(diagnostic)
        );
    return mwx_fixture_check(actual == expected, label, diagnostic);
}


void mwx_fixture_media_cursor_cases(MWXSceneScriptQuickJSFixture *fixture) {
    const char *media_playback_source =
        "let state=MediaPlaybackEvent.PLAYBACK_STOPPED;"
        "export function mediaPlaybackChanged(event){state=event.state;}"
        "export function update(value){"
        "if(MediaPlaybackEvent.PLAYBACK_PLAYING!==1||"
        "MediaPlaybackEvent.PLAYBACK_PAUSED!==2)throw new Error('enum');"
        "return value+state;}";
    fixture->media_playback_owner = mwx_scene_quickjs_owner_create(
        fixture->domain, media_playback_source, strlen(media_playback_source),
        20, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->media_playback_owner != NULL, "media playback compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->media_playback_owner, 20, 3, MWX_SCENE_QUICKJS_OK, 3,
        "media playback stopped initial state"
    );
    fixture->failures += mwx_fixture_media_playback(
        fixture->media_playback_owner, 20, 1, MWX_SCENE_QUICKJS_OK,
        "media playback playing event"
    );
    fixture->failures += mwx_fixture_update(
        fixture->media_playback_owner, 20, 3, MWX_SCENE_QUICKJS_OK, 4,
        "media playback event updates same owner state"
    );
    fixture->failures += mwx_fixture_media_playback(
        fixture->media_playback_owner, 20, 3, MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
        "invalid media playback state"
    );
    fixture->failures += mwx_fixture_media_playback(
        fixture->media_playback_owner, 21, 2, MWX_SCENE_QUICKJS_STALE_OWNER,
        "stale media playback owner"
    );

    const char *immutable_media_playback_source =
        "'use strict';export function update(value){"
        "MediaPlaybackEvent.PLAYBACK_STOPPED=9;return value;}";
    fixture->immutable_media_playback =
        mwx_scene_quickjs_owner_create(
            fixture->domain, immutable_media_playback_source,
            strlen(immutable_media_playback_source),
            21, fixture->diagnostic, sizeof(fixture->diagnostic)
        );
    fixture->failures += mwx_fixture_check(
        fixture->immutable_media_playback != NULL,
        "immutable media playback compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->immutable_media_playback, 21, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "MediaPlaybackEvent is immutable"
    );

    const char *playback_error_source =
        "export function mediaPlaybackChanged(){"
        "thisScene.getLayerByID(17).text='pending';"
        "throw new Error('playback');}"
        "export function update(value){return value;}";
    fixture->playback_error = mwx_scene_quickjs_owner_create(
        fixture->domain, playback_error_source, strlen(playback_error_source),
        22, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->playback_error != NULL, "media playback error compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->playback_error, 42, "media playback error owner identity"
    );
    fixture->failures += mwx_fixture_media_playback(
        fixture->playback_error, 22, 1, MWX_SCENE_QUICKJS_EXCEPTION,
        "media playback callback exception"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_layer_mutation_count(fixture->playback_error) == 0,
        "media playback exception releases authored text staging", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->playback_error, 22, 1, MWX_SCENE_QUICKJS_DISABLED, 0,
        "media playback callback disables only its owner"
    );
    fixture->failures += mwx_fixture_update(
        fixture->isolated, 2, 3, MWX_SCENE_QUICKJS_OK, 13,
        "media playback failure preserves peer owner"
    );

    const char *media_assign_failure_source =
        "export var scriptProperties=createScriptProperties()"
        ".addSlider({name:'factor',value:1}).finish();"
        "export function update(value){"
        "thisScene.getLayerByID(17).text='previous-callback';return value;}"
        "export function mediaPlaybackChanged(){}";
    fixture->media_assign_failure = mwx_scene_quickjs_owner_create(
        fixture->domain, media_assign_failure_source, strlen(media_assign_failure_source),
        62, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->media_assign_failure != NULL,
        "media properties assignment failure compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->media_assign_failure, 42,
        "media properties assignment failure owner identity"
    );
    fixture->failures += mwx_fixture_update(
        fixture->media_assign_failure, 62, 1, MWX_SCENE_QUICKJS_OK, 1,
        "media properties failure prerequisite stages authored text"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_layer_mutation_count(fixture->media_assign_failure) == 1,
        "media properties failure prerequisite mutation", fixture->diagnostic
    );
    MWXSceneQuickJSFrameInput media_assign_frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
    };
    MWXSceneQuickJSMediaPlaybackEvent media_assign_event = {
        .state = 1,
    };
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_dispatch_media_playback(
            fixture->media_assign_failure, 62, &media_assign_event,
            &media_assign_frame, "{", 1,
            fixture->diagnostic, sizeof(fixture->diagnostic)
        ) == MWX_SCENE_QUICKJS_EXCEPTION,
        "media properties assignment failure", fixture->diagnostic
    );
    MWXSceneQuickJSLifecycleSnapshot media_assign_lifecycle = {0};
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_layer_mutation_count(fixture->media_assign_failure) == 0 &&
            mwx_scene_quickjs_owner_lifecycle_snapshot(
                fixture->media_assign_failure, &media_assign_lifecycle
            ) == MWX_SCENE_QUICKJS_OK &&
            media_assign_lifecycle.pending_layer_mutation_count == 0 &&
            media_assign_lifecycle.active_timer_count == 0 &&
            media_assign_lifecycle.has_job_residue == 0 &&
            media_assign_lifecycle.callback_active == 0,
        "media properties failure releases prior text and is quiescent",
        fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->media_assign_failure, 62, 1, MWX_SCENE_QUICKJS_DISABLED, 0,
        "media properties assignment failure disables owner"
    );

    const char *media_properties_source =
        "let text='';"
        "export function mediaPropertiesChanged(event){"
        "text=event.title+' / '+event.artist;}"
        "export function update(value){return text||value;}";
    fixture->media_properties_owner = mwx_scene_quickjs_owner_create(
        fixture->domain, media_properties_source, strlen(media_properties_source),
        23, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->media_properties_owner != NULL, "media properties compile", fixture->diagnostic
    );
    uint32_t string_update_available = 0;
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_has_function(
            fixture->media_properties_owner, "update", 6, &string_update_available,
            fixture->diagnostic, sizeof(fixture->diagnostic)
        ) == MWX_SCENE_QUICKJS_OK && string_update_available == 1,
        "string update export", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update_string(
        fixture->media_properties_owner, 23, "Placeholder", MWX_SCENE_QUICKJS_OK,
        "Placeholder", "string authored fallback"
    );
    fixture->failures += mwx_fixture_media_properties(
        fixture->media_properties_owner, 23, "Song", "Artist", MWX_SCENE_QUICKJS_OK,
        "media properties event"
    );
    fixture->failures += mwx_fixture_update_string(
        fixture->media_properties_owner, 23, "Placeholder", MWX_SCENE_QUICKJS_OK,
        "Song / Artist", "media properties update string"
    );
    fixture->failures += mwx_fixture_media_properties(
        fixture->media_properties_owner, 24, "Stale", "Artist",
        MWX_SCENE_QUICKJS_STALE_OWNER, "stale media properties owner"
    );

    const char *media_timeline_source =
        "let progress=0;"
        "export function mediaTimelineChanged(event){"
        "if(!Object.isFrozen(event))throw new Error('mutable timeline');"
        "progress=event.duration===0?0:event.position/event.duration;}"
        "export function update(){return progress;}";
    fixture->media_timeline_owner = mwx_scene_quickjs_owner_create(
        fixture->domain, media_timeline_source, strlen(media_timeline_source),
        25, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->media_timeline_owner != NULL, "media timeline compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_media_timeline(
        fixture->media_timeline_owner, 25, 12.5, 100,
        MWX_SCENE_QUICKJS_OK, "media timeline event"
    );
    fixture->failures += mwx_fixture_update(
        fixture->media_timeline_owner, 25, 0, MWX_SCENE_QUICKJS_OK, 0.125,
        "media timeline update"
    );
    fixture->failures += mwx_fixture_media_timeline(
        fixture->media_timeline_owner, 25, -1, 100,
        MWX_SCENE_QUICKJS_INVALID_ARGUMENT, "negative media timeline"
    );
    fixture->failures += mwx_fixture_media_timeline(
        fixture->media_timeline_owner, 25, 1, INFINITY,
        MWX_SCENE_QUICKJS_INVALID_ARGUMENT, "non-finite media timeline"
    );
    fixture->failures += mwx_fixture_update(
        fixture->media_timeline_owner, 25, 0, MWX_SCENE_QUICKJS_OK, 0.125,
        "invalid media timeline preserves owner"
    );

    const char *cursor_source =
        "export function cursorEnter(event){"
        "if(!Object.isFrozen(event)||!Object.isFrozen(event.worldPosition)||"
        "!Object.isFrozen(event.localPosition))throw new Error('mutable cursor');"
        "shared.hover=event.worldPosition.x===10&&event.localPosition.y===0.25;}"
        "export function cursorLeave(event){shared.hover=false;}"
        "export function cursorDown(event){shared.pointerOrder='down';}"
        "export function cursorMove(event){"
        "if(shared.pointerOrder!=='down')throw new Error('cursor move order');"
        "shared.pointerOrder='move';}"
        "export function cursorUp(event){"
        "if(shared.pointerOrder!=='move')throw new Error('cursor order');"
        "shared.pointerOrder='up';}"
        "export function cursorClick(event){"
        "if(shared.pointerOrder!=='up')throw new Error('cursor order');"
        "shared.pointerOrder='click';}";
    fixture->cursor_owner = mwx_scene_quickjs_owner_create(
        fixture->domain, cursor_source, strlen(cursor_source),
        26, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->cursor_owner != NULL, "cursor owner compile", fixture->diagnostic);
    const char *cursor_consumer_source =
        "export var scriptProperties=createScriptProperties()"
        ".addSlider({name:'factor',value:2}).finish();"
        "let enabled=false;"
        "export function applyUserProperties(changed){"
        "if(!Object.isFrozen(changed))throw new Error('mutable properties');"
        "const copied=new Vec3(new Vec3(scriptProperties.factor));"
        "enabled=changed.enabled===true&&copied.x===3&&copied.y===3&&copied.z===3;}"
        "export function update(value){"
        "return shared.hover&&enabled?value*scriptProperties.factor:value;}";
    fixture->cursor_consumer = mwx_scene_quickjs_owner_create(
        fixture->domain, cursor_consumer_source, strlen(cursor_consumer_source),
        27, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->cursor_consumer != NULL, "cursor consumer compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_user_properties(
        fixture->cursor_consumer, 27, "{\"enabled\":true}", "{\"factor\":3}",
        "{\"enabled\":true}", MWX_SCENE_QUICKJS_OK,
        "initial user properties event"
    );
    fixture->failures += mwx_fixture_cursor_event(
        fixture->cursor_owner, 26, MWX_SCENE_QUICKJS_CURSOR_ENTER,
        MWX_SCENE_QUICKJS_OK, "cursor enter event"
    );
    fixture->failures += mwx_fixture_update(
        fixture->cursor_consumer, 27, 2, MWX_SCENE_QUICKJS_OK, 6,
        "cursor shared state reaches property owner"
    );
    fixture->failures += mwx_fixture_cursor_event(
        fixture->cursor_owner, 26, MWX_SCENE_QUICKJS_CURSOR_LEAVE,
        MWX_SCENE_QUICKJS_OK, "cursor leave event"
    );
    fixture->failures += mwx_fixture_cursor_event(
        fixture->cursor_owner, 26, MWX_SCENE_QUICKJS_CURSOR_DOWN,
        MWX_SCENE_QUICKJS_OK, "cursor down event"
    );
    fixture->failures += mwx_fixture_cursor_event(
        fixture->cursor_owner, 26, MWX_SCENE_QUICKJS_CURSOR_MOVE,
        MWX_SCENE_QUICKJS_OK, "cursor move event"
    );
    fixture->failures += mwx_fixture_cursor_event(
        fixture->cursor_owner, 26, MWX_SCENE_QUICKJS_CURSOR_UP,
        MWX_SCENE_QUICKJS_OK, "cursor up event"
    );
    fixture->failures += mwx_fixture_cursor_event(
        fixture->cursor_owner, 26, MWX_SCENE_QUICKJS_CURSOR_CLICK,
        MWX_SCENE_QUICKJS_OK, "cursor click event"
    );
    fixture->failures += mwx_fixture_update(
        fixture->cursor_consumer, 27, 2, MWX_SCENE_QUICKJS_OK, 2,
        "cursor leave restores authored value"
    );
    fixture->failures += mwx_fixture_cursor_event(
        fixture->cursor_owner, 28, MWX_SCENE_QUICKJS_CURSOR_ENTER,
        MWX_SCENE_QUICKJS_STALE_OWNER, "stale cursor owner"
    );

}

void mwx_fixture_audio_cases(MWXSceneScriptQuickJSFixture *fixture) {
    const char *audio_source =
        "const audio=engine.registerAudioBuffers();"
        "const same=engine.registerAudioBuffers(engine.AUDIO_RESOLUTION_16);"
        "const medium=engine.registerAudioBuffers(engine.AUDIO_RESOLUTION_32);"
        "const extended=engine.registerAudioBuffers(engine.AUDIO_RESOLUTION_64);"
        "const identity=audio.average;"
        "export function update(value){"
        "if(audio!==same||audio.average!==identity||"
        "!(audio.left instanceof Float32Array)||audio.left.length!==16||"
        "medium.left.length!==32||extended.left.length!==64)"
        "throw new Error('audio identity');"
        "const result=value+audio.left[0]+audio.right[1]+audio.average[2]+"
        "medium.left[31]+extended.right[63];"
        "audio.average[2]=99;return result;}";
    fixture->audio_owner = mwx_scene_quickjs_owner_create(
        fixture->domain, audio_source, strlen(audio_source),
        25, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->audio_owner != NULL, "audio owner compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_audio_registration_count(fixture->audio_owner) == 3,
        "audio resolutions and duplicate identity", fixture->diagnostic
    );
    float audio_left[16] = {0};
    float audio_right[16] = {0};
    audio_left[0] = 1;
    audio_right[1] = 2;
    audio_left[2] = 4;
    audio_right[2] = 2;
    float audio_left32[32] = {0};
    float audio_right32[32] = {0};
    audio_left32[31] = 4;
    float audio_left64[64] = {0};
    float audio_right64[64] = {0};
    audio_right64[63] = 5;
    fixture->failures += mwx_fixture_refresh_audio(
        fixture->audio_owner, 25, 16, audio_left, audio_right,
        MWX_SCENE_QUICKJS_OK, "audio snapshot refresh"
    );
    fixture->failures += mwx_fixture_refresh_audio(
        fixture->audio_owner, 25, 32, audio_left32, audio_right32,
        MWX_SCENE_QUICKJS_OK, "audio 32 snapshot refresh"
    );
    fixture->failures += mwx_fixture_refresh_audio(
        fixture->audio_owner, 25, 64, audio_left64, audio_right64,
        MWX_SCENE_QUICKJS_OK, "audio 64 snapshot refresh"
    );
    fixture->failures += mwx_fixture_update(
        fixture->audio_owner, 25, 1, MWX_SCENE_QUICKJS_OK, 16,
        "audio left right average and resolutions"
    );
    audio_left[0] = -1;
    fixture->failures += mwx_fixture_refresh_audio(
        fixture->audio_owner, 25, 16, audio_left, audio_right,
        MWX_SCENE_QUICKJS_INVALID_ARGUMENT, "invalid audio sample"
    );
    audio_left[0] = 1;
    fixture->failures += mwx_fixture_refresh_audio(
        fixture->audio_owner, 25, 16, audio_left, audio_right,
        MWX_SCENE_QUICKJS_OK, "audio same snapshot refresh"
    );
    fixture->failures += mwx_fixture_update(
        fixture->audio_owner, 25, 1, MWX_SCENE_QUICKJS_OK, 16,
        "audio host overwrites script mutation"
    );
    fixture->failures += mwx_fixture_refresh_audio(
        fixture->audio_owner, 26, 16, audio_left, audio_right,
        MWX_SCENE_QUICKJS_STALE_OWNER, "stale audio owner"
    );

    const char *invalid_audio_source =
        "const audio=engine.registerAudioBuffers(8);"
        "export function update(value){return value+audio.average[0];}";
    MWXSceneQuickJSOwner *invalid_audio = mwx_scene_quickjs_owner_create(
        fixture->domain, invalid_audio_source, strlen(invalid_audio_source),
        26, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        invalid_audio == NULL, "invalid audio resolution rejected", fixture->diagnostic
    );

    const char *callback_audio_source =
        "export function update(value){"
        "engine.registerAudioBuffers(16);return value;}";
    fixture->callback_audio = mwx_scene_quickjs_owner_create(
        fixture->domain, callback_audio_source, strlen(callback_audio_source),
        27, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->callback_audio != NULL, "callback audio owner compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->callback_audio, 27, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "audio registration is global-only"
    );

}
