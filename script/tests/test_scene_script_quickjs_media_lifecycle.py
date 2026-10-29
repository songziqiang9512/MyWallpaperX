#!/usr/bin/env python3

"""Focused QuickJS media-value, export-probe, and teardown contracts."""

from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

try:
    from .scene_vector_vm_test_support import C_SOURCES
except ImportError:
    from scene_vector_vm_test_support import C_SOURCES


ROOT = Path(__file__).resolve().parents[2]
SCENE_SCRIPT = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script"
QUICKJS = SCENE_SCRIPT / "QuickJSNG"


HARNESS = r'''
#include "SceneQuickJS.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int check(int condition, const char *label, const char *diagnostic) {
    if (condition) return 0;
    fprintf(stderr, "FAIL %s: %s\n", label, diagnostic ? diagnostic : "");
    return 1;
}

static int update_owner(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    double input,
    MWXSceneQuickJSResult expected,
    double expected_output,
    const char *label
) {
    char diagnostic[512] = {0};
    double output = 0;
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
    };
    MWXSceneQuickJSResult actual = mwx_scene_quickjs_owner_update_scalar(
        owner, generation, input, &frame, &output,
        diagnostic, sizeof(diagnostic)
    );
    return check(
        actual == expected &&
            (expected != MWX_SCENE_QUICKJS_OK || output == expected_output),
        label,
        diagnostic
    );
}

static int configure_owner_layer(
    MWXSceneQuickJSOwner *owner,
    int64_t layer_id,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSResult result =
        mwx_scene_quickjs_owner_configure_layer_identity(
            owner, layer_id, diagnostic, sizeof(diagnostic)
        );
    return check(result == MWX_SCENE_QUICKJS_OK, label, diagnostic);
}

static int configure_effects(
    MWXSceneQuickJSOwner *owner,
    uint32_t count,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSResult result =
        mwx_scene_quickjs_owner_configure_effect_catalog(
            owner, count, diagnostic, sizeof(diagnostic)
        );
    return check(result == MWX_SCENE_QUICKJS_OK, label, diagnostic);
}

static int configure_layers(MWXSceneQuickJSDomain *domain) {
    char diagnostic[512] = {0};
    const double origin[3] = {0, 0, 0};
    const double size[2] = {0, 0};
    MWXSceneQuickJSResult result =
        mwx_scene_quickjs_domain_configure_layer_catalog(
            domain, 1, 0, diagnostic, sizeof(diagnostic)
        );
    if (result == MWX_SCENE_QUICKJS_OK) {
        result = mwx_scene_quickjs_domain_set_layer_descriptor(
            domain, 0, 42, 0, 0, "media", strlen("media"), origin,
            size,
            diagnostic, sizeof(diagnostic)
        );
    }
    return check(result == MWX_SCENE_QUICKJS_OK, "layer catalog", diagnostic);
}

static int dispatch_colors(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    double primary_red,
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
        .has_thumbnail = 1,
        .primary_red = primary_red,
        .primary_green = 0.2,
        .primary_blue = 0.3,
        .secondary_red = 0,
        .secondary_green = 0,
        .secondary_blue = 0,
        .tertiary_red = 0.7,
        .tertiary_green = 0.8,
        .tertiary_blue = 0.9,
        .text_red = 1,
        .text_green = 1,
        .text_blue = 1,
        .high_contrast_red = 0,
        .high_contrast_green = 0,
        .high_contrast_blue = 0,
    };
    MWXSceneQuickJSResult actual =
        mwx_scene_quickjs_owner_dispatch_media_thumbnail(
            owner, generation, &event, &frame, "{}", 2,
            diagnostic, sizeof(diagnostic)
        );
    return check(actual == expected, label, diagnostic);
}

static int teardown_owner(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    MWXSceneQuickJSResult expected,
    uint32_t expected_invoked,
    uint32_t expected_threw,
    uint32_t expected_destroy_count,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25,
        .frame_time = 0,
        .runtime = 3,
    };
    uint32_t invoked = 0;
    uint32_t threw = 0;
    MWXSceneQuickJSResult actual =
        mwx_scene_quickjs_owner_teardown_with_provenance(
            owner, generation, &frame, NULL, 0, "{}", 2,
            &invoked, &threw, diagnostic, sizeof(diagnostic)
        );
    MWXSceneQuickJSLifecycleSnapshot snapshot = {0};
    MWXSceneQuickJSResult snapshot_result =
        mwx_scene_quickjs_owner_lifecycle_snapshot(owner, &snapshot);
    return check(
        actual == expected && invoked == expected_invoked &&
            threw == expected_threw &&
            snapshot_result == MWX_SCENE_QUICKJS_OK &&
            snapshot.teardown_started == 1 &&
            snapshot.destroy_callback_count == expected_destroy_count &&
            snapshot.active_timer_count == 0 &&
            snapshot.pending_layer_mutation_count == 0 &&
            snapshot.active_dynamic_layer_count == 0 &&
            snapshot.has_job_residue == 0 && snapshot.callback_active == 0,
        label,
        diagnostic
    );
}


static int check_playback_local_values(MWXSceneQuickJSDomain *domain) {
    char diagnostic[512] = {0};
    int failures = 0;
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25, .frame_time = 1.0 / 60.0, .runtime = 2.0,
    };
    const char *sources[] = {
        "'use strict';let held=null,input=-1;"
        "export function mediaPlaybackChanged(event){"
        "if(held&&held.state!==123)throw new Error('old event overwritten');"
        "input=event.state;"
        "if((event.state=1)!==1||!event.state)throw new Error('playing assignment');"
        "if((event.state=2)!==2||!event.state)throw new Error('paused assignment');"
        "if((event.state=0)!==0||event.state)throw new Error('stopped assignment');"
        "event.state=123;held=event;"
        "let rejected=false;try{MediaPlaybackEvent.PLAYBACK_PLAYING=9;}"
        "catch(e){rejected=true;}"
        "if(!rejected||MediaPlaybackEvent.PLAYBACK_PLAYING!==1)throw new Error('constant');"
        "}export function update(){return input*1000+held.state;}",
        "'use strict';let held=null,input=-1;"
        "export function mediaPlaybackChanged(event){"
        "if(held&&held.state!==124)throw new Error('second old event overwritten');"
        "input=event.state;event.state=124;held=event;"
        "}export function update(){return input*1000+held.state;}",
        "'use strict';let held=null,input=-1;"
        "export function mediaPlaybackChanged(event){"
        "if(held&&held.state!==input)throw new Error('observer event overwritten');"
        "input=event.state;held=event;"
        "}export function update(){return input*1000+held.state;}",
    };
    MWXSceneQuickJSOwner *owners[3] = {0};
    for (size_t i = 0; i < 3; ++i) {
        owners[i] = mwx_scene_quickjs_owner_create(
            domain, sources[i], strlen(sources[i]), 900 + i,
            diagnostic, sizeof(diagnostic)
        );
        failures += check(owners[i] != NULL, "local playback owner", diagnostic);
        if (owners[i] == NULL) goto cleanup;
    }
    const uint32_t states[] = {1, 2, 0, 1};
    for (size_t step = 0; step < 4; ++step) {
        MWXSceneQuickJSMediaPlaybackEvent event = {.state = states[step]};
        for (size_t i = 0; i < 3; ++i) {
            MWXSceneQuickJSResult result = mwx_scene_quickjs_owner_dispatch_media_playback(
                owners[i], 900 + i, &event, &frame, "{}", 2,
                diagnostic, sizeof(diagnostic)
            );
            failures += check(result == MWX_SCENE_QUICKJS_OK,
                "writable callback-local playback state", diagnostic);
            failures += check(event.state == states[step], "native payload unchanged", "");
        }
        for (size_t i = 0; i < 3; ++i) {
            double local = i == 0 ? 123 : (i == 1 ? 124 : states[step]);
            failures += update_owner(owners[i], 900 + i, 0,
                MWX_SCENE_QUICKJS_OK, states[step] * 1000 + local,
                "other callbacks and later events preserve local state");
        }
    }
    MWXSceneQuickJSMediaPlaybackEvent invalid = {.state = 3};
    failures += check(mwx_scene_quickjs_owner_dispatch_media_playback(
        owners[0], 900, &invalid, &frame, "{}", 2, diagnostic, sizeof(diagnostic)
    ) == MWX_SCENE_QUICKJS_INVALID_ARGUMENT, "native state remains bounded", diagnostic);
    MWXSceneQuickJSMediaPlaybackEvent valid = {.state = 2};
    failures += check(mwx_scene_quickjs_owner_dispatch_media_playback(
        owners[0], 901, &valid, &frame, "{}", 2, diagnostic, sizeof(diagnostic)
    ) == MWX_SCENE_QUICKJS_STALE_OWNER, "stale event rejected", diagnostic);
    failures += update_owner(owners[0], 900, 0, MWX_SCENE_QUICKJS_OK, 1123,
        "rejected events cannot change local state");
cleanup:
    for (size_t i = 0; i < 3; ++i) {
        if (owners[i] != NULL) mwx_scene_quickjs_owner_destroy(owners[i]);
    }
    return failures;
}

static char *video_fixture_path(const char *path, size_t length) {
    char *copy = malloc(length + 1);
    if (copy != NULL) { memcpy(copy, path, length); copy[length] = '\0'; }
    return copy;
}

static int publish_video_row(MWXSceneQuickJSDomain *domain, uint64_t generation,
                             const MWXSceneQuickJSVideoObservation *row) {
    char diagnostic[512] = {0};
    int failures = check(mwx_scene_quickjs_domain_begin_layer_snapshot(domain, generation, 0,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "prepared-only snapshot begins", diagnostic);
    failures += check(mwx_scene_quickjs_domain_stage_video_observations(domain, row, 1,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "renderer observation stages", diagnostic);
    failures += check(mwx_scene_quickjs_domain_commit_layer_snapshot(domain,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "renderer observation commits", diagnostic);
    mwx_scene_quickjs_domain_finalize_layer_snapshot(domain);
    return failures;
}

static MWXSceneQuickJSDomain *prepared_video_domain(int *failures) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSDomain *domain = mwx_scene_quickjs_domain_create(
        16 * 1024 * 1024, 512 * 1024, 200000, diagnostic, sizeof(diagnostic));
    *failures += check(domain != NULL, "prepared-only domain", diagnostic);
    if (domain == NULL) return NULL;
    *failures += check(mwx_scene_quickjs_domain_configure_layer_catalog(domain, 0, 0,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "no authored video or carrier layer", diagnostic);
    *failures += check(mwx_scene_quickjs_domain_set_asset_path_normalizer(domain, video_fixture_path)
        == MWX_SCENE_QUICKJS_OK, "external fixture paths bind", diagnostic);
    const MWXSceneQuickJSDynamicImageDescriptor models[] = {
        {.model_path="models/video-a.json", .model_path_length=sizeof("models/video-a.json")-1, .natural_size={200,100}, .is_video=1},
        {.model_path="models/renamed-b.json", .model_path_length=sizeof("models/renamed-b.json")-1, .natural_size={200,100}, .is_video=1},
        {.model_path="models/unbound.json", .model_path_length=sizeof("models/unbound.json")-1, .natural_size={200,100}, .is_video=1},
        {.model_path="models/still.json", .model_path_length=sizeof("models/still.json")-1, .natural_size={200,100}},
    };
    *failures += check(mwx_scene_quickjs_domain_configure_dynamic_image_catalog(domain, 4, models,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "prepared products configure once", diagnostic);
    const char *aliases[] = {"models/video-a.json", "models/renamed-b.json"};
    for (size_t index = 0; index < 2; ++index)
        *failures += check(mwx_scene_quickjs_domain_configure_prepared_video_source(domain,
            aliases[index], strlen(aliases[index]), 0, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
            "both models bind the renderer's single source row", diagnostic);
    MWXSceneQuickJSVideoObservation row = {.duration=10, .rate=1, .current_time=3,
        .loop=1, .is_playing=1, .available=1, .source_incarnation={11,22}};
    *failures += publish_video_row(domain, 1, &row);
    return domain;
}

static int prepared_video_callbacks(void) {
    int failures = 0; char diagnostic[512] = {0};
    MWXSceneQuickJSDomain *domain = prepared_video_domain(&failures);
    if (domain == NULL) return failures;
    const char *source =
        "let previous,last=0;export function update(v){"
        "if(previous){let stale=false;try{previous.play();}catch(e){stale=e instanceof TypeError;}"
        "if(!stale)throw Error('old consumer video revived');}"
        "if(v===0){const still=thisScene.createLayer('models/still.json');"
        "if(!still||still.getVideoTexture()!==undefined||thisScene.createLayer('models/unbound.json')!==null)throw Error('video qualification widened');"
        "thisScene.destroyLayer(still);}"
        "const a=thisScene.createLayer('models/video-a.json'),b=thisScene.createLayer('models/renamed-b.json');"
        "if(!a||!b||a.id>=last)throw Error('prepared birth');last=a.id;"
        "const av=a.getVideoTexture(),bv=b.getVideoTexture();"
        "if(!av||!bv||av.duration!==10||bv.rate!==1||av.getCurrentTime()!==3||bv.getCurrentTime()!==3)throw Error('source observation');"
        "av.play();bv.setCurrentTime(4);av.pause();"
        "if(av.getCurrentTime()!==3)throw Error('command journal mutated observation');previous=av;"
        "thisScene.destroyLayer(a);thisScene.destroyLayer(b);return v;}";
    MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_owner_create(domain, source, strlen(source),
        77, diagnostic, sizeof(diagnostic));
    failures += check(owner != NULL, "prepared-only controller", diagnostic);
    for (unsigned iteration = 0; owner != NULL && iteration < 5000 && failures == 0; ++iteration) {
        failures += update_owner(owner, 77, iteration, MWX_SCENE_QUICKJS_OK, iteration,
            "prepared create/get/play/destroy remains available beyond 4096 births");
        MWXSceneQuickJSMediaPlaybackCommand commands[3] = {{0}};
        failures += check(mwx_scene_quickjs_owner_media_playback_command_count(owner) == 3,
            "one callback retains exactly A-B-A commands", diagnostic);
        for (size_t index = 0; index < 3; ++index)
            failures += check(mwx_scene_quickjs_owner_media_playback_command_at(owner, index, &commands[index],
                diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK
                && commands[index].video_source_incarnation[0] == 11 && commands[index].video_source_incarnation[1] == 22,
                "authored command exports its observed source incarnation", diagnostic);
        failures += check(commands[0].kind == MWX_SCENE_QUICKJS_MEDIA_PLAY
            && commands[1].kind == MWX_SCENE_QUICKJS_MEDIA_SET_CURRENT_TIME && commands[1].number_value == 4
            && commands[2].kind == MWX_SCENE_QUICKJS_MEDIA_PAUSE && commands[0].layer_id == commands[2].layer_id
            && commands[0].layer_id != commands[1].layer_id && commands[0].callback_epoch == commands[2].callback_epoch
            && commands[0].callback_epoch != 0 && commands[0].ordinal == 0 && commands[1].ordinal == 1 && commands[2].ordinal == 2,
            "shared resource preserves consumer identity and emission order", diagnostic);
        mwx_scene_quickjs_owner_commit_layer_mutations(owner);
        MWXSceneQuickJSLifecycleSnapshot snapshot = {0};
        failures += check(mwx_scene_quickjs_owner_lifecycle_snapshot(owner, &snapshot) == MWX_SCENE_QUICKJS_OK
            && snapshot.active_dynamic_layer_count == 0, "zero carriers leave no instance alive", diagnostic);
    }
    const char *bad_source = "export function update(v){const a=thisScene.createLayer('models/video-a.json');a.getVideoTexture().play();throw Error('failed video owner');}";
    MWXSceneQuickJSOwner *bad = mwx_scene_quickjs_owner_create(domain, bad_source, strlen(bad_source), 78,
        diagnostic, sizeof(diagnostic));
    failures += check(bad != NULL, "failed video peer creates", diagnostic);
    if (owner != NULL && bad != NULL) {
        failures += update_owner(owner, 77, 5001, MWX_SCENE_QUICKJS_OK, 5001, "healthy peer journal remains pending");
        failures += update_owner(bad, 78, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0, "failed video owner rolls back");
        failures += check(mwx_scene_quickjs_owner_media_playback_command_count(bad) == 0
            && mwx_scene_quickjs_owner_media_playback_command_count(owner) == 3,
            "failed owner's command effects cannot replace healthy peer journal", diagnostic);
        mwx_scene_quickjs_owner_commit_layer_mutations(owner);
    }
    if (bad != NULL) mwx_scene_quickjs_owner_destroy(bad);
    if (owner != NULL) mwx_scene_quickjs_owner_destroy(owner);
    mwx_scene_quickjs_domain_destroy(domain);
    return failures;
}

static int video_source_row_aba(void) {
    int failures = 0; char diagnostic[512] = {0};
    MWXSceneQuickJSDomain *domain = prepared_video_domain(&failures);
    if (domain == NULL) return failures;
    const char *source =
        "let layer,id,old,fresh,latest,oldEnded=0,freshEnded=0,latestEnded=0;"
        "function stale(video){for(const f of [()=>video.play(),()=>video.getCurrentTime(),()=>video.rate]){"
        "let rejected=false;try{f();}catch(e){rejected=e instanceof TypeError;}if(!rejected)throw Error('source row rebound');}}"
        "export function update(v){if(v===0){layer=thisScene.createLayer('models/video-a.json');id=layer.id;"
        "old=layer.getVideoTexture();old.addEndedCallback(()=>oldEnded++);}"
        "if(v===1){if(layer.id!==id)throw Error('logical carrier changed');stale(old);fresh=layer.getVideoTexture();"
        "if(fresh.getCurrentTime()!==7||oldEnded!==0)throw Error('replacement observation');fresh.play();fresh.addEndedCallback(()=>freshEnded++);}"
        "if(v===2){if(oldEnded!==0||freshEnded!==1)throw Error('source EOF transferred or replayed');}"
        "if(v===3){stale(fresh);if(layer.getVideoTexture()!==undefined)throw Error('empty slot readable');"
        "if(thisScene.createLayer('models/video-a.json')!==null)throw Error('unavailable template instantiated');}"
        "if(v===4){stale(fresh);latest=layer.getVideoTexture();if(latest.getCurrentTime()!==1||freshEnded!==1)throw Error('ABA replacement');"
        "latest.addEndedCallback(()=>latestEnded++);}"
        "if(v===5){if(oldEnded!==0||freshEnded!==1||latestEnded!==1)throw Error('ABA EOF root transfer');thisScene.destroyLayer(layer);}return v;}";
    MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_owner_create(domain, source, strlen(source), 79,
        diagnostic, sizeof(diagnostic));
    failures += check(owner != NULL, "source identity controller", diagnostic);
    if (owner != NULL) {
        failures += update_owner(owner, 79, 0, MWX_SCENE_QUICKJS_OK, 0, "old source handle and EOF register");
        mwx_scene_quickjs_owner_commit_layer_mutations(owner);
        MWXSceneQuickJSVideoObservation row = {.duration=10, .rate=1, .current_time=7, .ended_generation=1,
            .loop=1, .is_playing=1, .available=1, .source_incarnation={33,44}};
        failures += publish_video_row(domain, 2, &row);
        failures += update_owner(owner, 79, 1, MWX_SCENE_QUICKJS_OK, 1, "same row and carrier reject old source handle");
        failures += check(mwx_scene_quickjs_owner_media_playback_command_count(owner) == 1,
            "only new source handle can emit a command", diagnostic);
        mwx_scene_quickjs_owner_commit_layer_mutations(owner);
        row.ended_generation = 2;
        failures += publish_video_row(domain, 3, &row);
        failures += update_owner(owner, 79, 2, MWX_SCENE_QUICKJS_OK, 2, "new source EOF arrives once");
        mwx_scene_quickjs_owner_commit_layer_mutations(owner);
        failures += update_owner(owner, 79, 2, MWX_SCENE_QUICKJS_OK, 2, "same EOF generation does not replay");
        mwx_scene_quickjs_owner_commit_layer_mutations(owner);
        row.available = 0;
        failures += publish_video_row(domain, 4, &row);
        failures += update_owner(owner, 79, 3, MWX_SCENE_QUICKJS_OK, 3, "cleared source row is unreadable");
        mwx_scene_quickjs_owner_commit_layer_mutations(owner);
        row.available = 1; row.current_time = 1; row.ended_generation = 3;
        row.source_incarnation[0] = 55; row.source_incarnation[1] = 66;
        failures += publish_video_row(domain, 5, &row);
        failures += update_owner(owner, 79, 4, MWX_SCENE_QUICKJS_OK, 4, "reused row has a new source incarnation");
        mwx_scene_quickjs_owner_commit_layer_mutations(owner);
        row.ended_generation = 4;
        failures += publish_video_row(domain, 6, &row);
        failures += update_owner(owner, 79, 5, MWX_SCENE_QUICKJS_OK, 5, "only latest source EOF root remains eligible");
        mwx_scene_quickjs_owner_commit_layer_mutations(owner);
        mwx_scene_quickjs_owner_destroy(owner);
    }
    mwx_scene_quickjs_domain_destroy(domain);
    return failures;
}

int main(void) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSDomain *domain = mwx_scene_quickjs_domain_create(
        2 * 1024 * 1024, 512 * 1024, 200000,
        diagnostic, sizeof(diagnostic)
    );
    if (check(domain != NULL, "domain", diagnostic)) return 1;

    int failures = prepared_video_callbacks() + video_source_row_aba();
    failures += configure_layers(domain);
    failures += check_playback_local_values(domain);
    const char *media_source =
        "'use strict';let score=0;"
        "export function mediaThumbnailChanged(event){"
        "if(!event.hasThumbnail||!Object.isFrozen(event)||"
        "!Object.isFrozen(event.primaryColor)||"
        "!Object.isFrozen(event.secondaryColor)||"
        "!Object.isFrozen(event.tertiaryColor)||"
        "!Object.isFrozen(event.textColor)||"
        "!Object.isFrozen(event.highContrastColor))throw new Error('freeze');"
        "if(event.primaryColor.toString()!=='0.1 0.2 0.3'||"
        "event.tertiaryColor.toString()!=='0.7 0.8 0.9'||"
        "new Vec3('0 0 0').toString()!=='0 0 0'||"
        "new Vec3('1, 2, 3').toString()!=='1 2 3')throw new Error('Vec3');"
        "let invalid=false;try{new Vec3('0 0');}catch(e){invalid=true;}"
        "if(!invalid)throw new Error('invalid Vec3 accepted');"
        "let rejected=false;try{event.primaryColor.x=0.9;}catch(e){rejected=true;}"
        "if(!rejected||event.primaryColor.x!==0.1)throw new Error('mutable');"
        "score=event.primaryColor.x+event.tertiaryColor.z+event.textColor.x+"
        "(event.secondaryColor=='0 0 0'?10:0);"
        "}export function update(){return score;}";
    MWXSceneQuickJSOwner *media = mwx_scene_quickjs_owner_create(
        domain, media_source, strlen(media_source),
        100, diagnostic, sizeof(diagnostic)
    );
    failures += check(media != NULL, "media colors compile", diagnostic);
    if (media == NULL) {
        mwx_scene_quickjs_domain_destroy(domain);
        return 1;
    }

    uint32_t available = 0;
    failures += check(
        mwx_scene_quickjs_owner_has_function(
            media, "mediaThumbnailChanged", 21, &available,
            diagnostic, sizeof(diagnostic)
        ) == MWX_SCENE_QUICKJS_OK && available == 1,
        "present callback export is explicit",
        diagnostic
    );
    available = 1;
    failures += check(
        mwx_scene_quickjs_owner_has_function(
            media, "cursorClick", 11, &available,
            diagnostic, sizeof(diagnostic)
        ) == MWX_SCENE_QUICKJS_OK && available == 0,
        "missing callback export is explicit",
        diagnostic
    );
    failures += check(
        mwx_scene_quickjs_owner_has_function(
            media, "", 0, &available, diagnostic, sizeof(diagnostic)
        ) == MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
        "callback export query failure is typed",
        diagnostic
    );
    failures += dispatch_colors(
        media, 100, 0.1, MWX_SCENE_QUICKJS_OK,
        "five-color event is an immutable Vec3 DTO"
    );
    failures += update_owner(
        media, 100, 0, MWX_SCENE_QUICKJS_OK, 12,
        "five-color event state reaches update"
    );
    failures += dispatch_colors(
        media, 100, NAN, MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
        "five-color event rejects nonfinite payload"
    );
    failures += dispatch_colors(
        media, 100, 1.1, MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
        "five-color event rejects out-of-range payload"
    );
    failures += update_owner(
        media, 100, 0, MWX_SCENE_QUICKJS_OK, 12,
        "invalid media payload does not disable its owner"
    );

    const char *peer_source =
        "export function update(value){return value+10;}";
    MWXSceneQuickJSOwner *peer = mwx_scene_quickjs_owner_create(
        domain, peer_source, strlen(peer_source),
        101, diagnostic, sizeof(diagnostic)
    );
    failures += check(peer != NULL, "peer owner compile", diagnostic);
    if (peer == NULL) {
        mwx_scene_quickjs_owner_destroy(media);
        mwx_scene_quickjs_domain_destroy(domain);
        return 1;
    }
    failures += update_owner(
        peer, 101, 2, MWX_SCENE_QUICKJS_OK, 12,
        "peer owner precondition"
    );
    // Production closes every callback journal at the shared frame barrier,
    // including owners that emitted no topology or value mutation.
    mwx_scene_quickjs_owner_commit_layer_mutations(media);
    mwx_scene_quickjs_owner_commit_layer_mutations(peer);

    const char *teardown_source =
        "export function init(value){"
        "thisScene.createLayer({text:'live'});"
        "engine.setInterval(()=>{},1000);return value;}"
        "export function destroy(){"
        "thisScene.createLayer({text:'destroy'});"
        "engine.setTimeout(()=>{},0);Promise.resolve().then(()=>{});}";
    MWXSceneQuickJSOwner *teardown = mwx_scene_quickjs_owner_create(
        domain, teardown_source, strlen(teardown_source),
        102, diagnostic, sizeof(diagnostic)
    );
    failures += check(teardown != NULL, "teardown owner compile", diagnostic);
    if (teardown != NULL) {
        failures += configure_owner_layer(
            teardown, 42, "teardown owner identity"
        );
        failures += update_owner(
            teardown, 102, 1, MWX_SCENE_QUICKJS_OK, 1,
            "teardown owner initialized"
        );
        MWXSceneQuickJSLifecycleSnapshot before_teardown = {0};
        failures += check(
            mwx_scene_quickjs_owner_lifecycle_snapshot(
                teardown, &before_teardown
            ) == MWX_SCENE_QUICKJS_OK &&
                before_teardown.active_timer_count == 1 &&
                before_teardown.active_dynamic_layer_count == 1,
            "teardown precondition has live resources",
            diagnostic
        );
        failures += teardown_owner(
            teardown, 102, MWX_SCENE_QUICKJS_OK, 1, 0, 1,
            "destroy succeeds once and resources quiesce"
        );
        failures += teardown_owner(
            teardown, 102, MWX_SCENE_QUICKJS_OK, 0, 0, 1,
            "teardown is idempotent"
        );
        failures += update_owner(
            teardown, 102, 1, MWX_SCENE_QUICKJS_STALE_OWNER, 0,
            "teardown revokes old generation"
        );
    }

    // A direct owner teardown must not discard a peer's still-provisional
    // topology transaction.  It reports a retryable hard failure, and the
    // caller can retry after the peer reaches the frame barrier.
    const char *retry_target_source =
        "export function update(value){"
        "thisScene.createLayer({name:'retry-target',text:'target'});"
        "return value;}";
    MWXSceneQuickJSOwner *retry_target = mwx_scene_quickjs_owner_create(
        domain, retry_target_source, strlen(retry_target_source),
        105, diagnostic, sizeof(diagnostic)
    );
    failures += check(
        retry_target != NULL, "teardown retry target compile", diagnostic
    );
    if (retry_target != NULL) {
        failures += update_owner(
            retry_target, 105, 1, MWX_SCENE_QUICKJS_OK, 1,
            "teardown retry target creates dynamic layer"
        );
        mwx_scene_quickjs_owner_commit_layer_mutations(retry_target);
    }

    const char *retry_blocker_source =
        "export function update(value){"
        "thisScene.createLayer({name:'retry-blocker',text:'blocker'});"
        "return value;}";
    MWXSceneQuickJSOwner *retry_blocker = mwx_scene_quickjs_owner_create(
        domain, retry_blocker_source, strlen(retry_blocker_source),
        106, diagnostic, sizeof(diagnostic)
    );
    failures += check(
        retry_blocker != NULL, "teardown retry blocker compile", diagnostic
    );
    if (retry_target != NULL && retry_blocker != NULL) {
        failures += update_owner(
            retry_blocker, 106, 1, MWX_SCENE_QUICKJS_OK, 1,
            "teardown retry blocker holds topology journal"
        );
        uint32_t retry_invoked = 0;
        uint32_t retry_threw = 0;
        MWXSceneQuickJSFrameInput retry_frame = {
            .time_of_day = 0.25, .frame_time = 0, .runtime = 3,
        };
        MWXSceneQuickJSResult retry_result =
            mwx_scene_quickjs_owner_teardown_with_provenance(
                retry_target, 105, &retry_frame, NULL, 0, "{}", 2,
                &retry_invoked, &retry_threw, diagnostic, sizeof(diagnostic)
            );
        MWXSceneQuickJSLifecycleSnapshot retry_snapshot = {0};
        failures += check(
            retry_result == MWX_SCENE_QUICKJS_EXCEPTION &&
                retry_invoked == 0 && retry_threw == 0 &&
                mwx_scene_quickjs_owner_lifecycle_snapshot(
                    retry_target, &retry_snapshot
                ) == MWX_SCENE_QUICKJS_OK &&
                retry_snapshot.teardown_started == 1 &&
                retry_snapshot.active_dynamic_layer_count == 1,
            "teardown waits for foreign topology transaction",
            diagnostic
        );
        mwx_scene_quickjs_owner_commit_layer_mutations(retry_blocker);
        MWXSceneQuickJSLifecycleSnapshot blocker_snapshot = {0};
        failures += check(
            mwx_scene_quickjs_owner_lifecycle_snapshot(
                retry_blocker, &blocker_snapshot
            ) == MWX_SCENE_QUICKJS_OK &&
                blocker_snapshot.active_dynamic_layer_count == 1,
            "foreign teardown failure preserves peer journal",
            diagnostic
        );
        retry_invoked = 0;
        retry_threw = 0;
        retry_result = mwx_scene_quickjs_owner_teardown_with_provenance(
            retry_target, 999, &retry_frame, NULL, 0, "{}", 2,
            &retry_invoked, &retry_threw, diagnostic, sizeof(diagnostic)
        );
        failures += check(
            retry_result == MWX_SCENE_QUICKJS_OK && retry_invoked == 0 &&
                retry_threw == 0 &&
                mwx_scene_quickjs_owner_lifecycle_snapshot(
                    retry_target, &retry_snapshot
                ) == MWX_SCENE_QUICKJS_OK &&
                retry_snapshot.active_dynamic_layer_count == 0,
            "teardown retry removes owner layers after peer release",
            diagnostic
        );
    }

    const char *exception_source =
        "export function update(value){return value;}"
        "export function destroy(){thisScene.createLayer({text:'discard'});"
        "engine.setInterval(()=>{},1);throw new Error('destroy failure');}";
    MWXSceneQuickJSOwner *exception = mwx_scene_quickjs_owner_create(
        domain, exception_source, strlen(exception_source),
        103, diagnostic, sizeof(diagnostic)
    );
    failures += check(exception != NULL, "teardown exception compile", diagnostic);
    if (exception != NULL) {
        failures += configure_owner_layer(
            exception, 42, "teardown exception identity"
        );
        failures += update_owner(
            exception, 103, 2, MWX_SCENE_QUICKJS_OK, 2,
            "teardown exception owner active"
        );
        failures += teardown_owner(
            exception, 103, MWX_SCENE_QUICKJS_EXCEPTION, 1, 1, 1,
            "destroy exception is proven and quiescent"
        );
        failures += update_owner(
            peer, 101, 2, MWX_SCENE_QUICKJS_OK, 12,
            "destroy exception preserves peer owner"
        );
    }

    const char *overflow_source =
        "export function update(value){return value;}"
        "export function destroy(){for(let i=0;i<17;i+=1)"
        "thisLayer.getEffect(i).executeMaterialFunction('clear');}";
    MWXSceneQuickJSOwner *overflow = mwx_scene_quickjs_owner_create(
        domain, overflow_source, strlen(overflow_source),
        104, diagnostic, sizeof(diagnostic)
    );
    failures += check(overflow != NULL, "teardown overflow compile", diagnostic);
    if (overflow != NULL) {
        failures += configure_owner_layer(
            overflow, 42, "teardown overflow identity"
        );
        failures += configure_effects(
            overflow, 17, "teardown overflow effect catalog"
        );
        failures += teardown_owner(
            overflow, 104, MWX_SCENE_QUICKJS_MUTATION_OVERFLOW, 1, 1, 1,
            "destroy mutation overflow is integrity-typed and quiescent"
        );
        failures += update_owner(
            peer, 101, 2, MWX_SCENE_QUICKJS_OK, 12,
            "destroy overflow preserves peer owner"
        );
    }

    if (overflow != NULL) mwx_scene_quickjs_owner_destroy(overflow);
    if (exception != NULL) mwx_scene_quickjs_owner_destroy(exception);
    if (retry_blocker != NULL) mwx_scene_quickjs_owner_destroy(retry_blocker);
    if (retry_target != NULL) mwx_scene_quickjs_owner_destroy(retry_target);
    if (teardown != NULL) mwx_scene_quickjs_owner_destroy(teardown);
    mwx_scene_quickjs_owner_destroy(peer);
    mwx_scene_quickjs_owner_destroy(media);
    mwx_scene_quickjs_domain_destroy(domain);
    return failures == 0 ? 0 : 1;
}
'''


class SceneScriptQuickJSMediaLifecycleTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        clang = shutil.which("clang")
        if clang is None:
            raise unittest.SkipTest("clang is required for the QuickJS contract gate")
        cls._temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-quickjs-media-lifecycle-"
        )
        root = Path(cls._temporary_directory.name)
        harness = root / "harness.c"
        binary = root / "harness"
        harness.write_text(HARNESS, encoding="utf-8")
        command = [
            clang,
            "-std=c11",
            "-O0",
            "-I",
            str(SCENE_SCRIPT),
            "-I",
            str(QUICKJS),
            *map(str, C_SOURCES),
            str(harness),
            "-lm",
            "-o",
            str(binary),
        ]
        compilation = subprocess.run(
            command, cwd=ROOT, capture_output=True, text=True
        )
        if compilation.returncode != 0:
            cls._temporary_directory.cleanup()
            raise AssertionError(
                "QuickJS media/lifecycle harness did not compile:\n"
                + compilation.stdout
                + compilation.stderr
            )
        cls._binary = binary

    @classmethod
    def tearDownClass(cls) -> None:
        cls._temporary_directory.cleanup()

    def test_media_value_export_and_teardown_contracts(self) -> None:
        completed = subprocess.run(
            [str(self._binary)], cwd=ROOT, capture_output=True, text=True
        )
        self.assertEqual(
            completed.returncode,
            0,
            completed.stdout + completed.stderr,
        )

    def test_export_probe_errors_fail_owner_construction(self) -> None:
        bridge = (ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptMediaEventBridge.swift").read_text(
            encoding="utf-8"
        )
        self.assertIn(
            "static func contains(_ name: String, owner: OpaquePointer) throws -> Bool",
            bridge,
        )
        self.assertIn("guard result == MWX_SCENE_QUICKJS_OK else", bridge)
        self.assertIn("throw failure(result, diagnostic: diagnostic)", bridge)
        self.assertNotIn(
            "return result == MWX_SCENE_QUICKJS_OK && available == 1",
            bridge,
        )



if __name__ == "__main__":
    unittest.main()
