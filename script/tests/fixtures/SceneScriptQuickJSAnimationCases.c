#include "SceneScriptQuickJSFixture.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

int mwx_fixture_animation_command(
    MWXSceneQuickJSOwner *owner,
    size_t index,
    MWXSceneQuickJSAnimationCommand expected,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSAnimationCommand command = 0;
    uint32_t target_index = 0;
    double frame = 0;
    uint64_t epoch = 0;
    uint32_t ordinal = 0;
    MWXSceneQuickJSResult result = mwx_scene_quickjs_owner_animation_command_at(
        owner, index, &command, &target_index, &frame, &epoch, &ordinal, diagnostic, sizeof(diagnostic)
    );
    return mwx_fixture_check(
        result == MWX_SCENE_QUICKJS_OK && command == expected && target_index == UINT32_MAX && epoch > 0,
        label,
        diagnostic
    );
}


static int mwx_fixture_retained_animation_lifetime(uint32_t property_object_is_layer) {
    int failures = 0;
    char diagnostic[512] = {0};
    MWXSceneQuickJSDomain *domain = mwx_scene_quickjs_domain_create(
        2 * 1024 * 1024, 512 * 1024, 100000, diagnostic, sizeof(diagnostic));
    if (domain == NULL) return mwx_fixture_check(0, "retained animation domain", diagnostic);
    failures += mwx_fixture_configure_layers(domain);
    const char *source =
        "let a;export function init(v){a=thisObject.getAnimation();shared.a=a;"
        "shared.obj=thisObject;shared.getter=thisObject.getAnimation;return v;}"
        "export function update(v){if(v===2)shared.obj.getAnimation().play();"
        "if(v===3)shared.getter().pause();return v;}"
        "export function mediaThumbnailChanged(e){a.stop();a.play();}"
        "export function applyUserProperties(p){if(p.later)engine.setTimeout(()=>a.pause(),0);}"
        "export function destroy(){a.stop();}";
    MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_owner_create(
        domain, source, strlen(source), 901, diagnostic, sizeof(diagnostic));
    failures += mwx_fixture_check(owner != NULL, "retained animation owner", diagnostic);
    failures += mwx_fixture_check(mwx_scene_quickjs_owner_configure_layer_identity(
        owner, 17, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "retained animation layer identity", diagnostic);
    failures += mwx_fixture_check(mwx_scene_quickjs_owner_set_property_object_scope(
        owner, property_object_is_layer, diagnostic, sizeof(diagnostic))
        == MWX_SCENE_QUICKJS_OK, "retained animation object scope", diagnostic);
    failures += mwx_fixture_check(mwx_scene_quickjs_owner_configure_current_animation(
        owner, 1, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "retained animation configure", diagnostic);
    failures += mwx_fixture_update(owner, 901, 1, MWX_SCENE_QUICKJS_OK, 1,
        "init captures current property animation");
    mwx_scene_quickjs_owner_commit_layer_mutations(owner);
    failures += mwx_fixture_update(owner, 901, 2, MWX_SCENE_QUICKJS_OK, 2,
        "saved property object accessor survives a later callback");
    failures += mwx_fixture_animation_command(owner, 0, MWX_SCENE_QUICKJS_ANIMATION_PLAY,
        "saved property object accessor play");
    mwx_scene_quickjs_owner_commit_layer_mutations(owner);
    failures += mwx_fixture_media_thumbnail(owner, 901, 1, MWX_SCENE_QUICKJS_OK,
        "init handle enters later media callback");
    failures += mwx_fixture_check(mwx_scene_quickjs_owner_animation_command_count(owner) == 2,
        "retained media callback produces exactly two commands", diagnostic);
    failures += mwx_fixture_animation_command(owner, 0, MWX_SCENE_QUICKJS_ANIMATION_STOP,
        "retained media stop");
    failures += mwx_fixture_animation_command(owner, 1, MWX_SCENE_QUICKJS_ANIMATION_PLAY,
        "retained media play");
    // A host admission rejection discards the bundle. The next callback must
    // not replay those commands; the capability itself remains valid.
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    failures += mwx_fixture_update(owner, 901, 1, MWX_SCENE_QUICKJS_OK, 1,
        "retained handle survives host rejection");
    failures += mwx_fixture_check(mwx_scene_quickjs_owner_animation_command_count(owner) == 0,
        "discarded commands do not replay", diagnostic);
    mwx_scene_quickjs_owner_commit_layer_mutations(owner);
    failures += mwx_fixture_update(owner, 902, 3, MWX_SCENE_QUICKJS_STALE_OWNER, 0,
        "wrong generation cannot execute retained animation");
    failures += mwx_fixture_update(owner, 901, 3, MWX_SCENE_QUICKJS_OK, 3,
        "retained handle still belongs to current generation");
    failures += mwx_fixture_animation_command(owner, 0, MWX_SCENE_QUICKJS_ANIMATION_PAUSE,
        "later update pause");
    mwx_scene_quickjs_owner_commit_layer_mutations(owner);
    failures += mwx_fixture_user_properties(owner, 901, "{\"later\":true}", "", "{\"later\":true}",
        MWX_SCENE_QUICKJS_OK, "schedule retained animation timer");
    mwx_scene_quickjs_owner_commit_layer_mutations(owner);
    failures += mwx_fixture_update_at(owner, 901, 1, 0.016, 3,
        MWX_SCENE_QUICKJS_OK, 1, "retained handle inside later timer");
    failures += mwx_fixture_animation_command(owner, 0, MWX_SCENE_QUICKJS_ANIMATION_PAUSE,
        "timer pause command");
    mwx_scene_quickjs_owner_commit_layer_mutations(owner);

    const char *peer_source =
        "export function update(v){for(const f of ['play','pause','stop']){"
        "let refused=false;try{shared.a[f]();}catch(e){refused=e instanceof TypeError;}"
        "if(!refused)throw new Error('foreign animation accepted');}"
        "for(const f of [()=>shared.obj.getAnimation(),()=>shared.getter()]){"
        "let refused=false;try{f();}catch(e){refused=e instanceof TypeError;}"
        "if(!refused)throw new Error('foreign animation accessor accepted');}"
        "thisObject.getAnimation().play();return v;}";
    MWXSceneQuickJSOwner *peer = mwx_scene_quickjs_owner_create(
        domain, peer_source, strlen(peer_source), 901, diagnostic, sizeof(diagnostic));
    failures += mwx_fixture_check(peer != NULL, "animation peer same generation", diagnostic);
    failures += mwx_fixture_check(mwx_scene_quickjs_owner_configure_current_animation(
        peer, 1, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "animation peer configure", diagnostic);
    failures += mwx_fixture_update(peer, 901, 1, MWX_SCENE_QUICKJS_OK, 1,
        "live foreign owner handle rejected without disabling healthy peer");
    failures += mwx_fixture_check(mwx_scene_quickjs_owner_animation_command_count(peer) == 1,
        "foreign animation cannot append peer commands", diagnostic);
    mwx_scene_quickjs_owner_commit_layer_mutations(peer);
    // Permanent retirement follows the host barrier, including the initial
    // catalog snapshot's rollback storage as well as every owner journal.
    mwx_scene_quickjs_domain_finalize_layer_snapshot(domain);
    MWXSceneQuickJSFrameInput frame = {.time_of_day=.25, .frame_time=.016, .runtime=3};
    uint32_t invoked = 0;
    failures += mwx_fixture_check(mwx_scene_quickjs_owner_teardown(owner, 901, &frame,
        "", 0, "{}", 2, &invoked, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK
        && invoked == 1, "destroy may use retained animation before revocation", diagnostic);
    failures += mwx_fixture_update(owner, 902, 1, MWX_SCENE_QUICKJS_DISABLED, 0,
        "retired owner cannot execute retained handle");
    mwx_scene_quickjs_owner_destroy(owner);
    // The JS object remains in shared after the native owner is freed. A
    // same-generation replacement cannot alias it even if malloc reuses memory.
    failures += mwx_fixture_update(peer, 901, 1, MWX_SCENE_QUICKJS_OK, 1,
        "freed owner's retained animation does not alias healthy peer");
    mwx_scene_quickjs_owner_commit_layer_mutations(peer);
    MWXSceneQuickJSOwner *rebuilt = mwx_scene_quickjs_owner_create(
        domain, peer_source, strlen(peer_source), 901, diagnostic, sizeof(diagnostic));
    failures += mwx_fixture_check(rebuilt != NULL, "same-generation owner rebuilt after destroy", diagnostic);
    failures += mwx_fixture_check(mwx_scene_quickjs_owner_configure_current_animation(
        rebuilt, 1, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "rebuilt animation configure", diagnostic);
    failures += mwx_fixture_update(rebuilt, 901, 1, MWX_SCENE_QUICKJS_OK, 1,
        "same-generation rebuild rejects freed owner's capability");
    failures += mwx_fixture_check(mwx_scene_quickjs_owner_animation_command_count(rebuilt) == 1,
        "rebuilt owner only stages its own play", diagnostic);
    mwx_scene_quickjs_owner_commit_layer_mutations(rebuilt);
    mwx_scene_quickjs_owner_destroy(rebuilt);
    const char *outside_source =
        "let refused=false;try{shared.a.play();}catch(e){refused=e instanceof TypeError;}"
        "if(!refused)throw new Error('animation ran outside callback');"
        "for(const f of [()=>shared.obj.getAnimation(),()=>shared.getter()]){"
        "let refused=false;try{f();}catch(e){refused=e instanceof TypeError;}"
        "if(!refused)throw new Error('animation accessor ran outside callback');}"
        "export function update(v){return v;}";
    MWXSceneQuickJSOwner *outside = mwx_scene_quickjs_owner_create(
        domain, outside_source, strlen(outside_source), 901, diagnostic, sizeof(diagnostic));
    failures += mwx_fixture_check(outside != NULL, "retained animation rejected during module evaluation", diagnostic);
    failures += mwx_fixture_update(outside, 901, 1, MWX_SCENE_QUICKJS_OK, 1,
        "module rejection preserves independent owner");
    mwx_scene_quickjs_owner_commit_layer_mutations(outside);

    const char *retry_source =
        "let a,n=0;export function init(v){if(++n===1){a=thisObject.getAnimation();"
        "a.play();return {};}a.stop();return v;}";
    MWXSceneQuickJSOwner *retry = mwx_scene_quickjs_owner_create(
        domain, retry_source, strlen(retry_source), 901, diagnostic, sizeof(diagnostic));
    failures += mwx_fixture_check(mwx_scene_quickjs_owner_configure_current_animation(
        retry, 1, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "init retry configure", diagnostic);
    failures += mwx_fixture_update(retry, 901, 1, MWX_SCENE_QUICKJS_BAD_RETURN, 0,
        "invalid init return rejects animation bundle");
    mwx_scene_quickjs_owner_discard_layer_mutations(retry);
    failures += mwx_fixture_update(retry, 901, 1, MWX_SCENE_QUICKJS_OK, 1,
        "retained property identity survives init admission retry");
    failures += mwx_fixture_check(mwx_scene_quickjs_owner_animation_command_count(retry) == 1,
        "retry has no rejected play prefix", diagnostic);
    failures += mwx_fixture_animation_command(retry, 0, MWX_SCENE_QUICKJS_ANIMATION_STOP,
        "init retry only stop");
    mwx_scene_quickjs_owner_commit_layer_mutations(retry);
    const char *throw_source =
        "let a;export function init(v){a=thisObject.getAnimation();shared.a=a;"
        "shared.obj=thisObject;shared.getter=thisObject.getAnimation;return v;}"
        "export function mediaThumbnailChanged(e){a.play();throw new Error('late');}";
    MWXSceneQuickJSOwner *thrower = mwx_scene_quickjs_owner_create(
        domain, throw_source, strlen(throw_source), 901, diagnostic, sizeof(diagnostic));
    failures += mwx_fixture_check(mwx_scene_quickjs_owner_configure_current_animation(
        thrower, 1, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "throwing retained animation configure", diagnostic);
    failures += mwx_fixture_update(thrower, 901, 1, MWX_SCENE_QUICKJS_OK, 1,
        "throwing retained handle initialized");
    mwx_scene_quickjs_owner_commit_layer_mutations(thrower);
    failures += mwx_fixture_media_thumbnail(thrower, 901, 1, MWX_SCENE_QUICKJS_EXCEPTION,
        "late throw rejects callback animation effects");
    failures += mwx_fixture_update(thrower, 901, 1, MWX_SCENE_QUICKJS_DISABLED, 0,
        "throw disables originating owner");
    failures += mwx_fixture_update(peer, 901, 1, MWX_SCENE_QUICKJS_OK, 1,
        "disabled owner's handle cannot be borrowed");
    mwx_scene_quickjs_owner_commit_layer_mutations(peer);
    mwx_scene_quickjs_owner_destroy(thrower);
    mwx_scene_quickjs_owner_destroy(retry);
    mwx_scene_quickjs_owner_destroy(outside);
    mwx_scene_quickjs_owner_destroy(peer);
    mwx_scene_quickjs_domain_destroy(domain);
    return failures;
}


int mwx_fixture_texture_animation_command(
    MWXSceneQuickJSOwner *owner,
    size_t index,
    uint32_t expected_kind,
    double expected_value,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSTextureAnimationCommand command = {0};
    MWXSceneQuickJSResult result =
        mwx_scene_quickjs_owner_texture_animation_command_at(
            owner, index, &command, diagnostic, sizeof(diagnostic)
        );
    return mwx_fixture_check(
        result == MWX_SCENE_QUICKJS_OK && command.layer_id == 42 &&
            command.kind == expected_kind &&
            fabs(command.number_value - expected_value) < 0.000001,
        label,
        diagnostic
    );
}


int mwx_fixture_configure_texture_animation(MWXSceneQuickJSDomain *domain) {
    char diagnostic[512] = {0};
    mwx_scene_quickjs_domain_finalize_layer_snapshot(domain);
    MWXSceneQuickJSResult result =
        mwx_scene_quickjs_domain_begin_layer_snapshot(
            domain, 2, 0, diagnostic, sizeof(diagnostic)
        );
    if (result == MWX_SCENE_QUICKJS_OK) {
        result = mwx_scene_quickjs_domain_reuse_layer_runtime_fields(
            domain, 0, diagnostic, sizeof(diagnostic)
        );
    }
    if (result == MWX_SCENE_QUICKJS_OK) {
        result = mwx_scene_quickjs_domain_reuse_layer_runtime_fields(
            domain, 1, diagnostic, sizeof(diagnostic)
        );
    }
    if (result == MWX_SCENE_QUICKJS_OK) {
        result =
            mwx_scene_quickjs_domain_update_layer_texture_animation_fields(
                domain, 1, 1, 4, 4, 1, 0, 1,
                1, 1, 1, diagnostic, sizeof(diagnostic)
            );
    }
    if (result == MWX_SCENE_QUICKJS_OK) {
        const double current_day[3] = {4, 5, 6};
        result = mwx_scene_quickjs_domain_set_layer_origin(
            domain, 1, current_day, diagnostic, sizeof(diagnostic)
        );
    }
    if (result == MWX_SCENE_QUICKJS_OK) {
        result = mwx_scene_quickjs_domain_commit_layer_snapshot(
            domain, diagnostic, sizeof(diagnostic)
        );
    }
    return mwx_fixture_check(
        result == MWX_SCENE_QUICKJS_OK,
        "texture animation snapshot",
        diagnostic
    );
}


void mwx_fixture_texture_animation_cases(MWXSceneScriptQuickJSFixture *fixture) {
    const char *texture_animation_source =
        "let animation;let calls=0;"
        "export function update(value){"
        "if(!animation)animation=thisLayer.getTextureAnimation();"
        "if(!animation||animation.frameCount!==4||animation.duration!==4)"
        "throw new Error('texture metadata');"
        "if(calls++===0){"
        "if(animation.rate!==1||!animation.isPlaying()||"
        "animation.getFrame()!==0)"
        "throw new Error('texture initial state');"
        "animation.setFrame(2);animation.rate=-2;animation.pause();"
        "if(animation.getFrame()!==2||animation.rate!==-2||"
        "animation.isPlaying())throw new Error('texture staged state');"
        "animation.join();"
        "if(animation.getFrame()!==1||animation.rate!==1||"
        "!animation.isPlaying())throw new Error('texture joined state');"
        "animation.setFrame(3.75);"
        "}else{"
        "if(animation.getFrame()!==0)"
        "throw new Error('texture snapshot leaked');"
        "animation.stop();"
        "if(animation.getFrame()!==0||animation.isPlaying())"
        "throw new Error('texture stop state');"
        "animation.play();"
        "if(!animation.isPlaying())throw new Error('texture play state');"
        "}return value;}";
    MWXSceneQuickJSOwner *texture_animation = mwx_scene_quickjs_owner_create(
        fixture->domain, texture_animation_source, strlen(texture_animation_source),
        63, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        texture_animation != NULL, "texture animation compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        texture_animation, 42, "texture animation owner identity"
    );
    fixture->failures += mwx_fixture_update(
        texture_animation, 63, 7, MWX_SCENE_QUICKJS_OK, 7,
        "texture animation first callback"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_texture_animation_command_count(
            texture_animation
        ) == 5,
        "texture animation first command count",
        fixture->diagnostic
    );
    fixture->failures += mwx_fixture_texture_animation_command(
        texture_animation, 0,
        MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_SET_FRAME, 2,
        "texture animation setFrame command"
    );
    fixture->failures += mwx_fixture_texture_animation_command(
        texture_animation, 1,
        MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_SET_RATE, -2,
        "texture animation rate command"
    );
    fixture->failures += mwx_fixture_texture_animation_command(
        texture_animation, 2,
        MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_PAUSE, 0,
        "texture animation pause command"
    );
    fixture->failures += mwx_fixture_texture_animation_command(
        texture_animation, 3,
        MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_JOIN, 0,
        "texture animation join command"
    );
    fixture->failures += mwx_fixture_texture_animation_command(
        texture_animation, 4,
        MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_SET_FRAME, 3,
        "texture animation post-join command"
    );
    fixture->failures += mwx_fixture_update(
        texture_animation, 63, 9, MWX_SCENE_QUICKJS_OK, 9,
        "texture animation persistent handle callback"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_texture_animation_command_count(
            texture_animation
        ) == 2,
        "texture animation second command count",
        fixture->diagnostic
    );
    fixture->failures += mwx_fixture_texture_animation_command(
        texture_animation, 0,
        MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_STOP, 0,
        "texture animation stop command"
    );
    fixture->failures += mwx_fixture_texture_animation_command(
        texture_animation, 1,
        MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_PLAY, 0,
        "texture animation play command"
    );
    mwx_scene_quickjs_owner_destroy(texture_animation);

    const char *invalid_texture_source =
        "export function update(value){"
        "thisLayer.getTextureAnimation().setFrame(4);return value;}";
    MWXSceneQuickJSOwner *invalid_texture = mwx_scene_quickjs_owner_create(
        fixture->domain, invalid_texture_source, strlen(invalid_texture_source),
        64, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        invalid_texture, 42, "invalid texture animation owner identity"
    );
    fixture->failures += mwx_fixture_update(
        invalid_texture, 64, 3, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "texture animation out-of-range frame rejected"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_texture_animation_command_count(
            invalid_texture
        ) == 0,
        "invalid texture animation emits no command",
        fixture->diagnostic
    );
    mwx_scene_quickjs_owner_destroy(invalid_texture);

    const char *missing_texture_source =
        "export function update(value){"
        "if(thisLayer.getTextureAnimation()!==undefined)"
        "throw new Error('unexpected texture animation');return value;}";
    MWXSceneQuickJSOwner *missing_texture = mwx_scene_quickjs_owner_create(
        fixture->domain, missing_texture_source, strlen(missing_texture_source),
        65, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        missing_texture, 17, "missing texture animation owner identity"
    );
    fixture->failures += mwx_fixture_update(
        missing_texture, 65, 5, MWX_SCENE_QUICKJS_OK, 5,
        "non-animated layer exposes no texture animation"
    );
    mwx_scene_quickjs_owner_destroy(missing_texture);
}

void mwx_fixture_effect_animation_cases(MWXSceneScriptQuickJSFixture *fixture) {
    const char *stale_effect_source =
        "let saved; export function update(value){"
        "if(!saved){saved=thisLayer.getEffect(0);return value;}"
        "saved.executeMaterialFunction('stale');return value;}";
    fixture->stale_effect = mwx_scene_quickjs_owner_create(
        fixture->domain, stale_effect_source, strlen(stale_effect_source),
        15, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->stale_effect != NULL, "stale effect compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_configure_effects(
        fixture->stale_effect, 1, 0, "known", "stale effect catalog"
    );
    fixture->failures += mwx_fixture_update(
        fixture->stale_effect, 15, 1, MWX_SCENE_QUICKJS_OK, 1,
        "effect handle callback scope"
    );
    fixture->failures += mwx_fixture_update(
        fixture->stale_effect, 15, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "stale effect handle rejected"
    );

    const char *animation_source =
        "export function init(value){thisObject.getAnimation().play();return value;}";
    fixture->animation_owner = mwx_scene_quickjs_owner_create(
        fixture->domain, animation_source, strlen(animation_source),
        16, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->animation_owner != NULL, "animation handle compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_configure_current_animation(
            fixture->animation_owner, 1, fixture->diagnostic, sizeof(fixture->diagnostic)
        ) == MWX_SCENE_QUICKJS_OK,
        "animation handle configure", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->animation_owner, 16, 1, MWX_SCENE_QUICKJS_OK, 1,
        "animation play callback"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_animation_command_count(fixture->animation_owner) == 1,
        "animation command count", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_animation_command(
        fixture->animation_owner, 0, MWX_SCENE_QUICKJS_ANIMATION_PLAY,
        "animation play mutation"
    );

    const char *stale_animation_source =
        "let saved;export function update(value){"
        "if(!saved){saved=thisObject.getAnimation();return value;}"
        "saved.pause();return value;}";
    fixture->stale_animation = mwx_scene_quickjs_owner_create(
        fixture->domain, stale_animation_source, strlen(stale_animation_source),
        17, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->stale_animation != NULL, "stale animation compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_configure_current_animation(
            fixture->stale_animation, 1, fixture->diagnostic, sizeof(fixture->diagnostic)
        ) == MWX_SCENE_QUICKJS_OK,
        "stale animation configure", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->stale_animation, 17, 1, MWX_SCENE_QUICKJS_OK, 1,
        "animation handle captured by owner"
    );
    fixture->failures += mwx_fixture_update(
        fixture->stale_animation, 17, 1, MWX_SCENE_QUICKJS_OK, 1,
        "animation handle survives same-owner callback"
    );
    fixture->failures += mwx_fixture_animation_command(fixture->stale_animation, 0,
        MWX_SCENE_QUICKJS_ANIMATION_PAUSE, "retained animation pause mutation");
    fixture->failures += mwx_fixture_retained_animation_lifetime(0);
    fixture->failures += mwx_fixture_retained_animation_lifetime(1);

    const char *named_animation_source =
        "export function update(value){thisObject.getAnimation('named');return value;}";
    fixture->named_animation = mwx_scene_quickjs_owner_create(
        fixture->domain, named_animation_source, strlen(named_animation_source),
        18, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->named_animation != NULL, "named animation compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_configure_current_animation(
            fixture->named_animation, 1, fixture->diagnostic, sizeof(fixture->diagnostic)
        ) == MWX_SCENE_QUICKJS_OK,
        "named animation configure", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->named_animation, 18, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "named animation lookup rejected"
    );

    const char *media_animation_source =
        "let a;export function init(value){a=thisObject.getAnimation();return value;}"
        "export function mediaThumbnailChanged(event){"
        "if(event.hasThumbnail){a.stop();a.play();}}";
    fixture->media_animation = mwx_scene_quickjs_owner_create(
        fixture->domain, media_animation_source, strlen(media_animation_source),
        19, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->media_animation != NULL, "media animation compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_configure_current_animation(
            fixture->media_animation, 1, fixture->diagnostic, sizeof(fixture->diagnostic)
        ) == MWX_SCENE_QUICKJS_OK,
        "media animation configure", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->media_animation, 19, 1, MWX_SCENE_QUICKJS_OK, 1,
        "media animation initialize"
    );
    fixture->failures += mwx_fixture_media_thumbnail(
        fixture->media_animation, 19, 0, MWX_SCENE_QUICKJS_OK,
        "media thumbnail absent event"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_animation_command_count(fixture->media_animation) == 0,
        "media absent command count", fixture->diagnostic
    );
    // Effect-visibility owner: `thisObject.visible` stages into the owner and
    // the update passthrough publishes it for the frame (batch B contract).
    const char *effect_visibility_source =
        "export function mediaThumbnailChanged(event)"
        "{ thisObject.visible = event.hasThumbnail; }";
    fixture->effect_visibility = mwx_scene_quickjs_owner_create(
        fixture->domain, effect_visibility_source, strlen(effect_visibility_source),
        49, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->effect_visibility != NULL, "effect visibility compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->effect_visibility, 17, "effect visibility owner identity"
    );
    char effect_visibility_diagnostic[512] = {0};
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_configure_effect_visibility_target(
            fixture->effect_visibility, 17, 2, true,
            effect_visibility_diagnostic, sizeof(effect_visibility_diagnostic)
        ) == MWX_SCENE_QUICKJS_OK,
        "effect visibility target configure", effect_visibility_diagnostic
    );
    fixture->failures += mwx_fixture_media_thumbnail(
        fixture->effect_visibility, 49, 0, MWX_SCENE_QUICKJS_OK,
        "effect visibility absent event"
    );
    fixture->failures += mwx_fixture_update(
        fixture->effect_visibility, 49, 1, MWX_SCENE_QUICKJS_OK, 0,
        "staged visible false publishes through the update"
    );
    fixture->failures += mwx_fixture_media_thumbnail(
        fixture->effect_visibility, 49, 1, MWX_SCENE_QUICKJS_OK,
        "effect visibility present event"
    );
    fixture->failures += mwx_fixture_update(
        fixture->effect_visibility, 49, 1, MWX_SCENE_QUICKJS_OK, 1,
        "staged visible true publishes through the update"
    );
    // D1 seed authority: the getter's read default is the configured binding
    // seed, not a hardcoded true. A false seed reads false until staged;
    // a staged write still overrides it.
    const char *seed_false_source =
        "export function update(){ return thisObject.visible ? 1 : 0; }";
    MWXSceneQuickJSOwner *seed_false_owner = mwx_scene_quickjs_owner_create(
        fixture->domain, seed_false_source, strlen(seed_false_source),
        50, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        seed_false_owner != NULL, "seed false compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        seed_false_owner, 17, "seed false owner identity"
    );
    char seed_false_diagnostic[512] = {0};
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_configure_effect_visibility_target(
            seed_false_owner, 17, 3, false,
            seed_false_diagnostic, sizeof(seed_false_diagnostic)
        ) == MWX_SCENE_QUICKJS_OK,
        "seed false target configure", seed_false_diagnostic
    );
    fixture->failures += mwx_fixture_update(
        seed_false_owner, 50, 1, MWX_SCENE_QUICKJS_OK, 0,
        "unstaged getter reads the false seed"
    );
    mwx_scene_quickjs_owner_destroy(seed_false_owner);

    // Effect visibility participates in the same frame commit/discard as layer
    // mutations. Per e-2026-10-16-bool-return, normal non-Bool returns keep the
    // journal; an actual throw discards it and disables that owner. Successful
    // callbacks rejected by the host remain the separate recoverable case.
    const char *visibility_transaction_sources[] = {
        "export function update(value) { thisObject.visible = !thisObject.visible; return value; }",
        "export function update(value) { thisObject.visible=false; throw new Error('visibility callback failure'); }",
        "export function mediaThumbnailChanged(event) { thisObject.visible = !thisObject.visible; }",
        "let first=true; export function update(value) { if(first) { first=false; return false; } return thisObject.visible; }",
        "export function update(value) { thisObject.visible = !thisObject.visible; return 'normal non-Bool'; }",
    };
    for (size_t test = 0; test < 5; ++test) {
        const char *source = visibility_transaction_sources[test];
        MWXSceneQuickJSResult visibility_creation = MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
        MWXSceneQuickJSOwner *visibility_owner =
            mwx_scene_quickjs_owner_create_effectful_bool_with_budget(
                fixture->domain, source, strlen(source), 149, 100000, &visibility_creation,
                fixture->diagnostic, sizeof(fixture->diagnostic)
            );
        fixture->failures += mwx_fixture_check(visibility_owner != NULL, "visibility transaction compile", fixture->diagnostic);
        if (visibility_owner == NULL) continue;
        fixture->failures += mwx_fixture_configure_owner_layer(visibility_owner, 17, "visibility transaction identity");
        fixture->failures += mwx_fixture_check(
            mwx_scene_quickjs_owner_configure_effect_visibility_target(
                visibility_owner, 17, 2, true, fixture->diagnostic, sizeof(fixture->diagnostic)
            ) == MWX_SCENE_QUICKJS_OK, "visibility transaction configure", fixture->diagnostic
        );
        if (test == 1) {
            fixture->failures += mwx_fixture_update_effectful_bool(visibility_owner, 149, 1,
                MWX_SCENE_QUICKJS_EXCEPTION, 0, "visibility failed write throws");
            fixture->failures += mwx_fixture_check(
                !mwx_scene_quickjs_owner_has_staged_effect_visibility(visibility_owner) &&
                    mwx_scene_quickjs_owner_layer_mutation_count(visibility_owner) == 0,
                "visibility failure exposes no journal", fixture->diagnostic
            );
            fixture->failures += mwx_fixture_update_effectful_bool(visibility_owner, 149, 1,
                MWX_SCENE_QUICKJS_DISABLED, 0, "visibility throw disables the failed owner");
            mwx_scene_quickjs_owner_destroy(visibility_owner);
            const char *healthy_source =
                "export function update(value) { return thisObject.visible; }";
            visibility_owner = mwx_scene_quickjs_owner_create_effectful_bool_with_budget(
                fixture->domain, healthy_source, strlen(healthy_source), 149, 100000,
                &visibility_creation, fixture->diagnostic, sizeof(fixture->diagnostic)
            );
            fixture->failures += mwx_fixture_check(visibility_owner != NULL,
                "visibility healthy successor compile", fixture->diagnostic);
            if (visibility_owner == NULL) continue;
            fixture->failures += mwx_fixture_configure_owner_layer(visibility_owner, 17,
                "visibility healthy successor identity");
            fixture->failures += mwx_fixture_check(
                mwx_scene_quickjs_owner_configure_effect_visibility_target(
                    visibility_owner, 17, 2, true, fixture->diagnostic, sizeof(fixture->diagnostic)
                ) == MWX_SCENE_QUICKJS_OK, "visibility healthy successor target", fixture->diagnostic
            );
            fixture->failures += mwx_fixture_update_effectful_bool(visibility_owner, 149, 1,
                MWX_SCENE_QUICKJS_OK, 1, "visibility healthy successor reads the uncommitted original seed");
        } else {
            if (test == 2) fixture->failures += mwx_fixture_media_thumbnail(visibility_owner, 149, 1,
                MWX_SCENE_QUICKJS_OK, "visibility event toggles authored seed");
            fixture->failures += mwx_fixture_update_effectful_bool(visibility_owner, 149, 1,
                MWX_SCENE_QUICKJS_OK, 0, "visibility first candidate hidden");
            mwx_scene_quickjs_owner_commit_layer_mutations(visibility_owner);
            if (test == 2) fixture->failures += mwx_fixture_media_thumbnail(visibility_owner, 149, 1,
                MWX_SCENE_QUICKJS_OK, "visibility event toggles committed value");
            fixture->failures += mwx_fixture_update_effectful_bool(visibility_owner, 149, 0,
                MWX_SCENE_QUICKJS_OK, test == 3 ? 0 : 1,
                "visibility getter reads committed current");
            if (test == 0) {
                // Discard a successfully evaluated but unsubmitted frame.
                mwx_scene_quickjs_owner_discard_layer_mutations(visibility_owner);
                fixture->failures += mwx_fixture_update_effectful_bool(visibility_owner, 149, 0,
                    MWX_SCENE_QUICKJS_OK, 1, "visibility frame discard restores committed current");
            }
            if (test == 2) {
                mwx_scene_quickjs_owner_commit_layer_mutations(visibility_owner);
                fixture->failures += mwx_fixture_media_thumbnail(visibility_owner, 149, 1,
                    MWX_SCENE_QUICKJS_OK, "visibility unconsumed event write");
                mwx_scene_quickjs_owner_discard_layer_mutations(visibility_owner);
                fixture->failures += mwx_fixture_update_effectful_bool(visibility_owner, 149, 1,
                    MWX_SCENE_QUICKJS_OK, 1, "visibility discard clears unconsumed event write");
            }
        }
        mwx_scene_quickjs_owner_destroy(visibility_owner);
    }
    fixture->failures += mwx_fixture_media_thumbnail(
        fixture->media_animation, 19, 1, MWX_SCENE_QUICKJS_OK,
        "media thumbnail present event"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_animation_command_count(fixture->media_animation) == 2,
        "media present command count", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_animation_command(
        fixture->media_animation, 0, MWX_SCENE_QUICKJS_ANIMATION_STOP,
        "media animation stop mutation"
    );
    fixture->failures += mwx_fixture_animation_command(
        fixture->media_animation, 1, MWX_SCENE_QUICKJS_ANIMATION_PLAY,
        "media animation play mutation"
    );

}
