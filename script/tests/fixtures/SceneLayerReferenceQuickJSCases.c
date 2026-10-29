#include "SceneQuickJSInternal.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char diagnostic[512];
static int failures;
static int checks;
static const char *first_layer_name = "Caption";
static const char *second_layer_name = "Peer";
static int64_t first_layer_id = 17, second_layer_id = 42;
static int fail_layer_reference_allocation;

void *layer_reference_calloc(size_t count, size_t size) {
    if (fail_layer_reference_allocation) { fail_layer_reference_allocation = 0; return NULL; }
    return calloc(count, size);
}

static void check(int condition, const char *label) {
    checks++;
    if (!condition) {
        failures++;
        fprintf(stderr, "FAIL %s: %s\n", label, diagnostic);
    }
}

static MWXSceneQuickJSDomain *domain(void) {
    MWXSceneQuickJSDomain *d = mwx_scene_quickjs_domain_create(
        16 * 1024 * 1024, 512 * 1024, 100000, diagnostic, sizeof(diagnostic));
    check(d != NULL, "domain creates");
    if (d == NULL) return NULL;
    check(mwx_scene_quickjs_domain_configure_layer_catalog(
        d, 2, 0, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "catalog configures");
    const double zero[3] = {0, 0, 0}, size[2] = {100, 100};
    const double one[3] = {1, 1, 1};
    for (uint32_t i = 0; i < 2; ++i) {
        const char *name = i == 0 ? first_layer_name : second_layer_name;
        check(mwx_scene_quickjs_domain_set_layer_runtime_descriptor(
            d, i, i == 0 ? first_layer_id : second_layer_id, 0, 0, name, strlen(name), zero, size,
            one, zero, 1, 1, "seed", 4, "", 0, 12, one,
            diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
            "text descriptor publishes");
        check(mwx_scene_quickjs_domain_set_layer_mutation_capabilities(
            d, i, 1, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
            "text mutation capability publishes");
    }
    return d;
}

static void publish_video_observation(MWXSceneQuickJSDomain *d, const MWXSceneQuickJSVideoObservation *video,
                                      uint32_t bound_layer, bool awaiting_outcome) {
    check(mwx_scene_quickjs_domain_begin_layer_snapshot(d, d->layer_snapshot_generation + 1, 0,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "video row transaction begins");
    for (uint32_t index = 0; index < d->authored_layer_count; ++index)
        check(mwx_scene_quickjs_domain_reuse_layer_runtime_fields(d, index, diagnostic, sizeof(diagnostic))
            == MWX_SCENE_QUICKJS_OK, "video row retains authored fields");
    check(mwx_scene_quickjs_domain_stage_video_observations(d, video, 1, diagnostic, sizeof(diagnostic))
        == MWX_SCENE_QUICKJS_OK, "real observation table stages");
    if (bound_layer != UINT32_MAX)
        check(mwx_scene_quickjs_domain_update_layer_video_source(d, bound_layer, 0, diagnostic, sizeof(diagnostic))
            == MWX_SCENE_QUICKJS_OK, "authored consumer binds the observed source");
    check(mwx_scene_quickjs_domain_commit_layer_snapshot(d, diagnostic, sizeof(diagnostic))
        == MWX_SCENE_QUICKJS_OK, "video row transaction commits");
    if (!awaiting_outcome) mwx_scene_quickjs_domain_finalize_layer_snapshot(d);
}



static void run(MWXSceneQuickJSOwner *o, uint64_t generation, double runtime,
                const char *input, MWXSceneQuickJSResult expected,
                const char *expected_error, const char *label) {
    MWXSceneQuickJSFrameInput frame = {.frame_time = 0.016, .runtime = runtime};
    char output[256] = {0}; size_t length = 0;
    memset(diagnostic, 0, sizeof(diagnostic));
    MWXSceneQuickJSResult actual = mwx_scene_quickjs_owner_update_string(
        o, generation, input, strlen(input), &frame, "", 0, "{}", 2,
        output, sizeof(output), &length, diagnostic, sizeof(diagnostic));
    check(actual == expected, label);
    if (expected == MWX_SCENE_QUICKJS_OK)
        check(length == strlen(input) && memcmp(output, input, length) == 0,
              "String typed output preserves input");
    if (expected_error != NULL)
        check(strstr(diagnostic, expected_error) != NULL, "original TypeError identifies guard family");
    printf("{\"case\":\"%s\",\"status\":%d,\"mutations\":%zu}\n",
        label, actual, mwx_scene_quickjs_owner_layer_mutation_count(o));
}





static MWXSceneQuickJSOwner *at(MWXSceneQuickJSDomain *d, const char *source,
                                int64_t id, uint64_t generation, int value_only) {
    MWXSceneQuickJSOwner *o = value_only
        ? mwx_scene_quickjs_owner_create_value_only_with_budget(d, source, strlen(source),
            generation, 100000, NULL, diagnostic, sizeof(diagnostic))
        : mwx_scene_quickjs_owner_create(d, source, strlen(source),
            generation, diagnostic, sizeof(diagnostic));
    check(o != NULL, "owner creates through public ABI");
    if (o == NULL) return NULL;
    check(mwx_scene_quickjs_owner_configure_layer_identity(o, id, diagnostic,
        sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "explicit target configures");
    check(mwx_scene_quickjs_owner_set_property_object_scope(o, 1, diagnostic,
        sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "layer property scope configures");
    return o;
}

static void journal_text(MWXSceneQuickJSOwner *o, int64_t id, const char *text) {
    int found = 0;
    for (size_t i = 0; i < mwx_scene_quickjs_owner_layer_mutation_count(o); ++i) {
        MWXSceneQuickJSLayerMutation value = {0};
        check(mwx_scene_quickjs_owner_layer_mutation_at(o, i, &value, diagnostic,
            sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "typed journal reads");
        if (value.layer_id != id) continue;
        check(value.dynamic == 0 && value.text != NULL && strcmp(value.text, text) == 0,
            "reference mutation retains original authored referent");
        found++;
    }
    check(found == 1, "original referent appears once in executing owner journal");
}

static void shared_lookup_case(const char *lookup, const char *write,
                               int64_t expected_id, int retire_creator) {
    MWXSceneQuickJSDomain *d = domain();
    char source[512];
    snprintf(source, sizeof(source),
        "export function update(v){shared.ref=%s;return v;}", lookup);
    MWXSceneQuickJSOwner *producer = at(d, source, 17, 91, 0);
    run(producer, 91, 1, "publish", MWX_SCENE_QUICKJS_OK, NULL,
        "producer publishes an ordinary reference");
    mwx_scene_quickjs_owner_commit_layer_mutations(producer);
    snprintf(source, sizeof(source),
        "export function update(v){thisLayer.text='prefix';%s;return v;}", write);
    MWXSceneQuickJSOwner *consumer = at(d, source, 42, 91, 0);
    if (retire_creator) { mwx_scene_quickjs_owner_destroy(producer); producer = NULL; }
    run(consumer, 91, 2, "accepted", MWX_SCENE_QUICKJS_OK,
        NULL,
        "same-scene reference used by another owner");
    {
        check(mwx_scene_quickjs_owner_layer_mutation_count(consumer)
            == (expected_id == 42 ? 1 : 2), "journal belongs to executing owner");
        journal_text(consumer, expected_id, "accepted");
        if (expected_id != 42) journal_text(consumer, 42, "prefix");
    }
    if (producer != NULL) check(mwx_scene_quickjs_owner_layer_mutation_count(producer) == 0,
        "producer journal receives no consumer mutation");
    mwx_scene_quickjs_owner_discard_layer_mutations(consumer);
    mwx_scene_quickjs_owner_destroy(consumer);
    if (producer != NULL) mwx_scene_quickjs_owner_destroy(producer);
    mwx_scene_quickjs_domain_destroy(d);
}

static void protected_receiver_and_generation(void) {
    MWXSceneQuickJSDomain *d = domain();
    MWXSceneQuickJSOwner *producer = at(d,
        "export function update(v){shared.ref=thisLayer;return v;}", 17, 91, 0);
    run(producer, 91, 1, "publish", MWX_SCENE_QUICKJS_OK, NULL,
        "late-bound receiver publishes");
    MWXSceneQuickJSOwner *consumer = at(d,
        "export function update(v){thisLayer.text='prefix';shared.ref.text=v;return v;}",
        42, 91, 0);
    run(consumer, 91, 2, "foreign", MWX_SCENE_QUICKJS_OK,
        NULL,
        "configured owner receiver keeps original referent across owners");
    journal_text(consumer, 17, "foreign");
    mwx_scene_quickjs_owner_discard_layer_mutations(consumer);
    mwx_scene_quickjs_owner_destroy(consumer);
    mwx_scene_quickjs_owner_destroy(producer);
    producer = at(d,
        "export function update(v){shared.ref=thisScene.getLayer('Caption');return v;}",
        17, 91, 0);
    run(producer, 91, 1, "publish", MWX_SCENE_QUICKJS_OK, NULL,
        "reference captures creating generation");
    consumer = at(d,
        "export function update(v){shared.ref.text=v;return v;}", 42, 92, 0);
    run(consumer, 92, 2, "local-token", MWX_SCENE_QUICKJS_OK,
        NULL,
        "different owner local token shares same domain reference");
    journal_text(consumer, 17, "local-token");
    mwx_scene_quickjs_owner_discard_layer_mutations(consumer);
    run(consumer, 91, 3, "stale-receiver", MWX_SCENE_QUICKJS_STALE_OWNER,
        NULL, "stale receiver generation refuses before callback");
    mwx_scene_quickjs_owner_destroy(consumer);
    mwx_scene_quickjs_owner_destroy(producer);
    mwx_scene_quickjs_domain_destroy(d);
}

static void protected_dynamic_and_atomicity(void) {
    MWXSceneQuickJSDomain *d = domain();
    MWXSceneQuickJSOwner *producer = at(d,
        "export function update(v){shared.dynamic=thisScene.createLayer({text:'owned'});"
        "shared.ref=thisScene.getLayer('Caption');return v;}", 17, 91, 0);
    run(producer, 91, 1, "publish", MWX_SCENE_QUICKJS_OK, NULL,
        "dynamic creator publishes protected reference");
    mwx_scene_quickjs_owner_commit_layer_mutations(producer);
    MWXSceneQuickJSOwner *consumer = at(d,
        "export function update(v){let refused=false;try{shared.dynamic.text='foreign';}"
        "catch(e){refused=true;}if(!refused)throw new Error('foreign accepted');"
        "thisLayer.text=v;return v;}", 42, 91, 0);
    run(consumer, 91, 2, "safe", MWX_SCENE_QUICKJS_OK, NULL,
        "caught foreign dynamic refusal preserves valid write");
    journal_text(consumer, 42, "safe");
    mwx_scene_quickjs_owner_discard_layer_mutations(consumer);
    mwx_scene_quickjs_owner_destroy(consumer);
    consumer = at(d,
        "export function update(v){thisLayer.text='prefix';shared.ref.text=v;"
        "throw new Error('intentional transaction failure');}", 42, 91, 0);
    run(consumer, 91, 3, "discard", MWX_SCENE_QUICKJS_EXCEPTION,
        "intentional transaction failure",
        "uncaught failure rolls back all authored mutations");
    check(mwx_scene_quickjs_owner_layer_mutation_count(consumer) == 0,
        "failed shared write transaction publishes nothing");
    mwx_scene_quickjs_owner_destroy(consumer);
    mwx_scene_quickjs_owner_destroy(producer);
    mwx_scene_quickjs_domain_destroy(d);
}

static void value_only_capabilities(void) {
    const char *sources[] = {
        "export function update(v){thisScene.getLayer('Caption').visible=false;return v;}",
        "export function update(v){thisScene.getLayer('Peer').visible=false;return v;}",
        "export function update(v){thisScene.getLayer('Caption').text='forbidden';return v;}",
    };
    MWXSceneQuickJSDomain *d = domain();
    for (int i = 0; i < 3; ++i) {
        MWXSceneQuickJSOwner *o = at(d, sources[i], 17, 91, 1);
        uint32_t output = 0;
        MWXSceneQuickJSFrameInput frame = {.runtime = 1, .frame_time = 0.016};
        MWXSceneQuickJSResult result = mwx_scene_quickjs_owner_update_bool_with_properties(
            o, 91, 1, &frame, NULL, 0, "{}", 2, &output, diagnostic, sizeof(diagnostic));
        check(result == (i == 0 ? MWX_SCENE_QUICKJS_OK : MWX_SCENE_QUICKJS_EXCEPTION),
            "value-only lookup keeps original field and target capabilities");
        check(mwx_scene_quickjs_owner_layer_mutation_count(o) == (i == 0 ? 1 : 0),
            "value-only unsafe write stages nothing");
        mwx_scene_quickjs_owner_discard_layer_mutations(o);
        mwx_scene_quickjs_owner_destroy(o);
    }
    mwx_scene_quickjs_domain_destroy(d);
}


static void publication_and_retirement(void) {
    MWXSceneQuickJSDomain *d = domain();
    const char *source = "export function update(v){shared.ref=thisLayer;return v;}";
    MWXSceneQuickJSOwner *producer = mwx_scene_quickjs_owner_create(d,
        source, strlen(source), 117, diagnostic, sizeof(diagnostic));
    check(producer != NULL, "unconfigured native receiver constructs");
    run(producer, 117, 1, "capture", MWX_SCENE_QUICKJS_OK, NULL,
        "unconfigured receiver may be retained before target publication");
    MWXSceneQuickJSOwner *consumer = at(d,
        "export function update(v){shared.ref.text=v;return v;}", 42, 205, 0);
    run(consumer, 205, 2, "unconfigured", MWX_SCENE_QUICKJS_EXCEPTION,
        "layer mutation target is not an owned dynamic layer", "unconfigured referent cannot redirect to actor");
    mwx_scene_quickjs_owner_destroy(consumer);
    consumer = at(d, "export function update(v){shared.ref.text=v;return v;}", 42, 205, 0);
    check(mwx_scene_quickjs_owner_configure_layer_identity(producer, 999,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
        "invalid publication rejects without a target");
    run(consumer, 205, 3, "invalid", MWX_SCENE_QUICKJS_EXCEPTION,
        "layer mutation target is not an owned dynamic layer", "failed publication leaves receiver unavailable");
    mwx_scene_quickjs_owner_destroy(consumer);
    consumer = at(d, "export function update(v){shared.ref.text=v;return v;}", 42, 205, 0);
    check(mwx_scene_quickjs_owner_configure_layer_identity(producer, 17,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "valid publication reuses original native receiver");
    run(consumer, 205, 4, "configured", MWX_SCENE_QUICKJS_OK,
        NULL,
        "same retained object sees published creator referent");
    journal_text(consumer, 17, "configured");
    mwx_scene_quickjs_owner_discard_layer_mutations(consumer);
    check(mwx_scene_quickjs_owner_configure_layer_identity(producer, 42,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
        "repeat configure cannot retarget persistent reference");
    mwx_scene_quickjs_owner_destroy(producer);
    run(consumer, 205, 5, "retained", MWX_SCENE_QUICKJS_OK,
        NULL,
        "static field reference survives creator owner retirement");
    journal_text(consumer, 17, "retained");
    mwx_scene_quickjs_owner_discard_layer_mutations(consumer);
    mwx_scene_quickjs_owner_destroy(consumer);
    mwx_scene_quickjs_domain_destroy(d);
}


static void owner_receiver_metadata(void) {
    MWXSceneQuickJSDomain *d = domain();
    const int64_t ids[] = {17, 42};
    const char *names[] = {"Caption", "Peer"};
    for (int i = 0; i < 2; ++i) {
        char source[1024];
        snprintf(source, sizeof(source),
            "export function update(v){"
            "if(thisLayer.id!==%lld||thisLayer.name!=='%s'||thisObject!==thisLayer)"
            "throw new Error('metadata referent');"
            "if(Object.getPrototypeOf(thisLayer)!==Object.prototype)"
            "throw new Error('owner receiver prototype');"
            "const d=Object.getOwnPropertyDescriptor(thisLayer,'text');"
            "if(!d||!d.enumerable||d.configurable||typeof d.get!=='function'||typeof d.set!=='function')"
            "throw new Error('property surface');"
            "if(typeof thisLayer.getEffect!=='function'||typeof thisLayer.getEffectCount!=='function'||"
            "typeof thisLayer.getParent!=='function'||typeof thisLayer.getChildren!=='function')"
            "throw new Error('layer API shape');"
            "if(thisLayer.getParent()!==undefined||thisLayer.getChildren().length!==0)"
            "throw new Error('hierarchy referent');return v;}",
            (long long)ids[i], names[i]);
        MWXSceneQuickJSOwner *o = at(d, source, ids[i], 91, 0);
        run(o, 91, 1, "metadata", MWX_SCENE_QUICKJS_OK, NULL,
            "each owner native receiver keeps its target and original JS surface");
        check(mwx_scene_quickjs_owner_layer_mutation_count(o) == 0,
            "metadata reads stage no mutation");
        mwx_scene_quickjs_owner_destroy(o);
    }
    mwx_scene_quickjs_domain_destroy(d);
}


static void owner_without_layer_catalog(void) {
    MWXSceneQuickJSDomain *d = mwx_scene_quickjs_domain_create(
        16 * 1024 * 1024, 512 * 1024, 100000, diagnostic, sizeof(diagnostic));
    check(d != NULL, "domain without a layer catalog constructs");
    if (d == NULL) return;
    const char *source = "export function update(v){return v+1;}";
    MWXSceneQuickJSOwner *o = mwx_scene_quickjs_owner_create(d, source, strlen(source),
        300, diagnostic, sizeof(diagnostic));
    check(o != NULL, "native owner factory does not read placeholder catalog storage");
    check(mwx_scene_quickjs_owner_configure_layer_identity(o, 17, diagnostic,
        sizeof(diagnostic)) == MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
        "empty catalog refuses target publication");
    MWXSceneQuickJSFrameInput frame = {.runtime = 1, .frame_time = 0.016};
    double output = 0;
    MWXSceneQuickJSResult result = mwx_scene_quickjs_owner_update_scalar(
        o, 300, 5, &frame, &output, diagnostic, sizeof(diagnostic));
    check(result == MWX_SCENE_QUICKJS_OK && output == 6,
        "ordinary scalar owner without a layer still executes");
    check(mwx_scene_quickjs_owner_layer_mutation_count(o) == 0,
        "empty catalog scalar owner stages no mutation");
    mwx_scene_quickjs_owner_destroy(o);
    mwx_scene_quickjs_domain_destroy(d);
}

static int emission_calls;

static MWXSceneQuickJSResult owned_emission(
    void *opaque, MWXSceneQuickJSOwner *owner,
    const MWXSceneQuickJSParticlePlaybackCommand *command,
    MWXSceneQuickJSParticlePlaybackState *projection
) {
    (void)opaque; (void)owner; (void)command;
    emission_calls++;
    *projection = (MWXSceneQuickJSParticlePlaybackState){.available = 1, .live = 1};
    return MWX_SCENE_QUICKJS_OK;
}

static void attached_capabilities_remain_owner_bound(void) {
    const char *operations[] = {
        "shared.get.call({})", "shared.set.call({},'unsafe')",
        "Object.create(shared.ref).text", "shared.ref.getParent()",
        "shared.ref.getChildren()", "shared.ref.getTransformMatrix()",
        "shared.ref.getVideoTexture()", "shared.ref.getTextureAnimation()",
        "shared.particle.play()", "shared.particle.pause()", "shared.particle.stop()",
        "shared.particle.isPlaying()", "shared.ref.emitParticles(1)",
        "shared.bound.play()", "shared.bound.pause()", "shared.bound.stop()", "shared.bound.isPlaying()",
        "shared.ref.instance.alpha=0.25", "shared.instance.alpha=0.25",
        "shared.video.play()", "shared.texture.play()",
    };
    for (size_t i = 0; i < sizeof(operations) / sizeof(operations[0]); ++i) {
        MWXSceneQuickJSDomain *d = domain();
        check(mwx_scene_quickjs_domain_begin_layer_snapshot(d, 1, 0,
            diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
            "attachment snapshot begins");
        const double one[3] = {1, 1, 1}, zero[3] = {0, 0, 0};
        for (uint32_t layer = 0; layer < 2; ++layer)
            check(mwx_scene_quickjs_domain_update_layer_runtime_fields(d, layer,
                one, zero, 0, 1, 1, 0, 1, "seed", 4, "", 0, 12, one,
                diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
                "attachment runtime field snapshot stages");
        const MWXSceneQuickJSVideoObservation video = {.duration=4, .rate=1, .available=1, .source_incarnation={11,22}};
        check(mwx_scene_quickjs_domain_stage_video_observations(d, &video, 1,
            diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "video fixture row stages");
        check(mwx_scene_quickjs_domain_update_layer_video_source(d, 0, 0,
            diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "video fixture consumer binds");
        check(mwx_scene_quickjs_domain_update_layer_texture_animation_fields(d, 0, 1,
            4, 4, 1, 0, 0, 1, 0, 0, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
            "texture fixture publishes");
        check(mwx_scene_quickjs_domain_update_layer_sound_fields(d, 0, 1, 0,
            diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
            "sound fixture publishes");
        MWXSceneQuickJSParticlePlaybackState playback = {.available = 1};
        for (uint32_t layer = 0; layer < 2; ++layer)
            check(mwx_scene_quickjs_domain_update_layer_particle_playback(d, layer, playback,
            diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
            "particle playback fixture publishes");
        check(mwx_scene_quickjs_domain_update_layer_particle_instance_alpha(d, 0, 1, 1,
            diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
            "particle instance fixture publishes");
        const double world[16] = {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1};
        check(mwx_scene_quickjs_domain_update_layer_world_transform(d, 0, world,
            diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
            "world transform fixture publishes");
        check(mwx_scene_quickjs_domain_commit_layer_snapshot(d,
            diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
            "attachment snapshot commits");
        emission_calls = 0;
        mwx_scene_quickjs_domain_begin_particle_frame(d, owned_emission, NULL, NULL,
            100000, 1024 * 1024);
        MWXSceneQuickJSOwner *producer = at(d,
            "export function update(v){const sound=thisScene.getLayerByID('17');shared.ref=sound;"
            "shared.particle=thisScene.getLayerByID('42');shared.bound=thisLayer;"
            "shared.soundRun=()=>{sound.play();if(sound.isPlaying()!==true)throw Error('play');"
            "sound.pause();if(sound.isPlaying()!==false)throw Error('pause');sound.stop();"
            "if(sound.isPlaying()!==false)throw Error('stop');};shared.soundQuery=()=>sound.isPlaying();"
            "const d=Object.getOwnPropertyDescriptor(shared.ref,'text');"
            "shared.get=d.get;shared.set=d.set;shared.instance=shared.ref.instance;"
            "shared.video=shared.ref.getVideoTexture();"
            "shared.texture=shared.ref.getTextureAnimation();"
            "if(shared.get.call({})!=='seed')throw new Error('own captured getter');"
            "shared.set.call({},'seed');return v;}", 17, 91, 0);
        run(producer, 91, 1, "publish", MWX_SCENE_QUICKJS_OK, NULL,
            "creator may use captured fallback and attached capabilities");
        mwx_scene_quickjs_owner_discard_layer_mutations(producer);
        char source[1024];
        snprintf(source, sizeof(source),
            "export function update(v){let refused=false;try{%s;}catch(e){"
            "refused=e instanceof TypeError;}if(!refused)throw new Error('foreign capability accepted');"
            "thisLayer.text=v;return v;}", operations[i]);
        MWXSceneQuickJSOwner *consumer = at(d, source, 42, 92, 0);
        run(consumer, 92, 2, "safe", MWX_SCENE_QUICKJS_OK, NULL, operations[i]);
        journal_text(consumer, 42, "safe");
        check(mwx_scene_quickjs_owner_layer_mutation_count(consumer) == 1 &&
            mwx_scene_quickjs_owner_media_playback_command_count(consumer) == 0 &&
            mwx_scene_quickjs_owner_texture_animation_command_count(consumer) == 0 &&
            mwx_scene_quickjs_owner_particle_playback_command_count(consumer) == 0 &&
            emission_calls == 0,
            "foreign attachment stages no operation in the executing journal");
        mwx_scene_quickjs_owner_destroy(consumer);
        if (i == 0) {
            consumer = at(d,
                "export function update(v){const ref=thisScene.getLayerByID('17');"
                "ref.instance.alpha=0.8;ref.getVideoTexture().play();"
                "ref.getTextureAnimation().play();ref.play();ref.emitParticles(1);"
                "if(ref.getParent()!==undefined||ref.getChildren().length!==0||"
                "!ref.getTransformMatrix())throw new Error('fresh hierarchy');"
                "thisLayer.text=v;return v;}", 42, 92, 0);
            run(consumer, 92, 3, "fresh", MWX_SCENE_QUICKJS_OK, NULL,
                "active owner fresh lookup retains original attached capabilities");
            check(mwx_scene_quickjs_owner_media_playback_command_count(consumer) == 2 &&
                mwx_scene_quickjs_owner_texture_animation_command_count(consumer) == 1 &&
                mwx_scene_quickjs_owner_particle_playback_command_count(consumer) == 1 &&
                emission_calls == 1,
                "fresh lookup reaches original typed native command channels");
            mwx_scene_quickjs_owner_destroy(consumer);
            consumer = at(d, "export function update(v){shared.soundRun();thisLayer.text=v;return v;}", 42, 92, 0);
            run(consumer, 92, 4, "sound", MWX_SCENE_QUICKJS_OK, NULL, "shared closure controls authored Sound");
            check(mwx_scene_quickjs_owner_media_playback_command_count(consumer) == 3 &&
                mwx_scene_quickjs_owner_media_playback_command_count(producer) == 0,
                "Sound commands belong only to executing owner");
            const uint32_t actions[] = {MWX_SCENE_QUICKJS_MEDIA_PLAY, MWX_SCENE_QUICKJS_MEDIA_PAUSE, MWX_SCENE_QUICKJS_MEDIA_STOP};
            for (size_t index = 0; index < 3; ++index) {
                MWXSceneQuickJSMediaPlaybackCommand command = {0};
                check(mwx_scene_quickjs_owner_media_playback_command_at(consumer,index,&command,diagnostic,sizeof(diagnostic))
                    == MWX_SCENE_QUICKJS_OK && command.layer_id == 17 && command.destination == MWX_SCENE_QUICKJS_MEDIA_SOUND_LAYER
                    && command.kind == actions[index], "shared Sound retains referent and command order");
            }
            mwx_scene_quickjs_owner_discard_layer_mutations(consumer);
            mwx_scene_quickjs_owner_destroy(producer); producer = NULL;
            run(consumer, 92, 5, "retired", MWX_SCENE_QUICKJS_OK, NULL, "creator retirement does not retire authored Sound");
            check(mwx_scene_quickjs_owner_media_playback_command_count(consumer) == 3, "live target still receives Sound commands");
            mwx_scene_quickjs_owner_discard_layer_mutations(consumer);
            MWXSceneQuickJSOwner *read_only = at(d,
                "export function update(v){const media=thisScene.getLayerByID('17');if(media.isPlaying()!==false)throw Error('query');"
                "let denied=false;try{media.play();}catch(e){denied=e instanceof TypeError;}"
                "if(!denied)throw Error('readonly control');return v;}", 42, 93, 1);
            MWXSceneQuickJSFrameInput query_frame = {.frame_time=0.016,.runtime=6}; uint32_t queried = 0;
            check(mwx_scene_quickjs_owner_update_bool_with_properties(read_only,93,1,&query_frame,
                NULL,0,"{}",2,&queried,diagnostic,sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK && queried == 1,
                "readonly Sound lookup queries but cannot control live target");
            check(mwx_scene_quickjs_owner_media_playback_command_count(read_only) == 0, "readonly shared Sound stages no command");
            mwx_scene_quickjs_owner_destroy(read_only);
            d->layers[0].configured = false;
            run(consumer, 92, 7, "removed", MWX_SCENE_QUICKJS_EXCEPTION, "layer playback unavailable", "target retirement invalidates retained Sound");
            check(mwx_scene_quickjs_owner_media_playback_command_count(consumer) == 0, "retired Sound target stages no command");
            d->layers[0].configured = true;
            mwx_scene_quickjs_owner_destroy(consumer);
        }
        mwx_scene_quickjs_domain_end_particle_frame(d);
        mwx_scene_quickjs_owner_destroy(producer);
        mwx_scene_quickjs_domain_destroy(d);
    }
}

static void retired_owner_attachments(void) {
    const char *captures[] = {"thisLayer", "thisLayer", "thisLayer.getEffect(0)",
        "thisScene", "thisScene", "engine.registerAsset", "thisObject", "thisObject"};
    const char *calls[] = {"shared.ref.getEffectCount()", "shared.ref.getEffect(0)",
        "shared.ref.executeMaterialFunction('refresh')", "shared.ref.getLayerCount()",
        "shared.ref.getLayerByID('17')", "shared.ref('font.ttf')",
        "shared.ref.visible", "shared.ref.visible=false"};
    for (size_t i = 0; i < sizeof(captures) / sizeof(captures[0]); ++i) {
        MWXSceneQuickJSDomain *d = domain();
        char source[512];
        snprintf(source, sizeof(source),
            "export function update(v){shared.ref=%s;return v;}", captures[i]);
        MWXSceneQuickJSOwner *producer;
        if (i >= 6) {
            producer = mwx_scene_quickjs_owner_create(d, source, strlen(source),
                91, diagnostic, sizeof(diagnostic));
            check(producer != NULL, "effect object owner constructs");
            check(mwx_scene_quickjs_owner_configure_effect_visibility_target(producer,
                17, 0, 1, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
                "effect visibility target configures");
        } else producer = at(d, source, 17, 91, 0);
        check(mwx_scene_quickjs_owner_configure_effect_catalog(producer, 1,
            diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
            "owner effect catalog publishes");
        check(mwx_scene_quickjs_owner_set_effect_name(producer, 0, "glow", 4,
            diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
            "owner effect name publishes");
        run(producer, 91, 1, "capture", MWX_SCENE_QUICKJS_OK, NULL,
            "creator publishes attached method");
        mwx_scene_quickjs_owner_destroy(producer);
        snprintf(source, sizeof(source),
            "export function update(v){let refused=false;try{%s;}catch(e){"
            "refused=e instanceof TypeError;}if(!refused)throw new Error('retired capability accepted');"
            "thisLayer.text=v;return v;}", calls[i]);
        MWXSceneQuickJSOwner *consumer = at(d, source, 42, 92, 0);
        run(consumer, 92, 2, "safe", MWX_SCENE_QUICKJS_OK, NULL, calls[i]);
        journal_text(consumer, 42, "safe");
        check(mwx_scene_quickjs_owner_material_function_count(consumer) == 0,
            "retired material capability does not redirect to a replacement owner");
        mwx_scene_quickjs_owner_destroy(consumer);
        mwx_scene_quickjs_domain_destroy(d);
    }
}

static void namespace_rejection_and_recovery(void) {
    const char *operations[] = {
        "shared.scene.createLayer({text:'unsafe'})",
        "shared.scene.sortLayer(thisLayer,0)",
    };
    const char *valid = "const made=thisScene.createLayer({text:'owned'});"
        "if(!made)throw new Error('fresh creation');thisScene.sortLayer(made,0);"
        "thisLayer.text=v;";
    for (size_t operation = 0; operation < 2; ++operation) {
        for (int retired = 0; retired < 2; ++retired) {
            for (int caught = 0; caught < 2; ++caught) {
                MWXSceneQuickJSDomain *d = domain();
                MWXSceneQuickJSOwner *producer = at(d,
                    "export function update(v){shared.scene=thisScene;return v;}",
                    17, 91, 0);
                run(producer, 91, 1, "publish", MWX_SCENE_QUICKJS_OK, NULL,
                    "namespace creator publishes owner-bound methods");
                if (retired) {
                    mwx_scene_quickjs_owner_destroy(producer);
                    producer = NULL;
                }
                char source[1024];
                if (caught) snprintf(source, sizeof(source),
                    "export function update(v){if(v==='fresh'){%s return v;}"
                    "thisLayer.text=v;let refused=false;try{%s;}catch(e){"
                    "refused=e instanceof TypeError;}if(!refused)throw new Error('namespace accepted');"
                    "return v;}", valid, operations[operation]);
                else snprintf(source, sizeof(source),
                    "export function update(v){thisLayer.text=v;%s;return v;}",
                    operations[operation]);
                MWXSceneQuickJSOwner *consumer = at(d, source, 42, 92, 0);
                run(consumer, 92, 2, "prefix", caught ? MWX_SCENE_QUICKJS_OK
                    : MWX_SCENE_QUICKJS_EXCEPTION, caught ? NULL
                    : (operation == 0 ? "createLayer expects" : "sortLayer expects"),
                    retired ? "retired namespace rejects before owner reads"
                            : "foreign namespace rejects before owner reads");
                check(mwx_scene_quickjs_owner_layer_mutation_count(consumer) == (caught ? 1 : 0),
                    "caught refusal retains prefix and uncaught refusal rolls it back");
                check(mwx_scene_quickjs_owner_pending_layer_topology_identity(consumer) == 0,
                    "rejected namespace creates no topology transaction");
                mwx_scene_quickjs_owner_discard_layer_mutations(consumer);
                if (!caught) {
                    mwx_scene_quickjs_owner_destroy(consumer);
                    snprintf(source, sizeof(source), "export function update(v){%s return v;}", valid);
                    consumer = at(d, source, 42, 93, 0);
                }
                run(consumer, caught ? 92 : 93, 3, "fresh", MWX_SCENE_QUICKJS_OK, NULL,
                    "failure is followed by a valid owner create and sort transaction");
                check(mwx_scene_quickjs_owner_layer_mutation_count(consumer) == 2 &&
                    mwx_scene_quickjs_owner_pending_layer_topology_identity(consumer) != 0,
                    "valid creator reaches original value and topology journals");
                mwx_scene_quickjs_owner_discard_layer_mutations(consumer);
                mwx_scene_quickjs_owner_destroy(consumer);
                if (producer != NULL) mwx_scene_quickjs_owner_destroy(producer);
                mwx_scene_quickjs_domain_destroy(d);
            }
        }
    }
}

static void shared_basic_fields(void) {
    for (int retired = 0; retired < 2; ++retired) {
        MWXSceneQuickJSDomain *d = domain();
        MWXSceneQuickJSOwner *producer = at(d,
            "export function update(v){shared.ref=thisLayer;return v;}", 17, 91, 0);
        run(producer, 91, 1, "publish", MWX_SCENE_QUICKJS_OK, NULL,
            "creator publishes a native receiver with its full field surface");
        if (retired) { mwx_scene_quickjs_owner_destroy(producer); producer = NULL; }
        MWXSceneQuickJSOwner *consumer = at(d,
            "export function update(v){const r=shared.ref;"
            "if(r.id!==17||r.name!=='Caption'||r.text!=='seed'||r.pointsize!==12||"
            "r.origin.x!==0||r.size.x!==100||r.scale.x!==1||r.angles.x!==0||"
            "!r.visible||!r.solid||r.perspective||r.alpha!==1||r.color.x!==1||r.font!==undefined)"
            "throw new Error('shared basic fields');"
            "r.alpha=0.75;r.color=new Vec3(0.5,0.5,0.5);r.text=v;return v;}",
            42, 92, 0);
        run(consumer, 92, 2, "fields", MWX_SCENE_QUICKJS_OK, NULL,
            retired ? "retired creator basic metadata and value fields remain available"
                    : "shared receiver metadata and value fields remain available");
        journal_text(consumer, 17, "fields");
        mwx_scene_quickjs_owner_destroy(consumer);
        if (producer != NULL) mwx_scene_quickjs_owner_destroy(producer);
        mwx_scene_quickjs_domain_destroy(d);
    }
}

static void namespace_method_table(void) {
    MWXSceneQuickJSDomain *d = domain();
    MWXSceneQuickJSOwner *producer = at(d,
        "export function update(v){shared.scene=thisScene;return v;}", 17, 91, 0);
    run(producer, 91, 1, "publish", MWX_SCENE_QUICKJS_OK, NULL,
        "namespace method table publishes");
    const char *source = "export function update(v){const s=shared.scene;"
        "const entries=[['getLayer',[0]],['getLayerByID',['17']],['getLayerCount',[]],"
        "['getInitialLayerConfig',[thisLayer]],['enumerateLayers',[]],"
        "['createLayer',[{text:'unsafe'}]],['sortLayer',[thisLayer,0]],"
        "['destroyLayer',[thisLayer]]];for(const [name,args]of entries){"
        "let refused=false;try{s[name](...args);}catch(e){refused=e instanceof TypeError;}"
        "if(!refused)throw new Error('namespace method accepted '+name);}"
        "if(s.getLayerIndex(thisLayer)!==-1)throw new Error('stale namespace index');"
        "thisLayer.text=v;return v;}";
    MWXSceneQuickJSOwner *consumer = at(d, source, 42, 92, 0);
    run(consumer, 92, 2, "foreign", MWX_SCENE_QUICKJS_OK, NULL,
        "all namespace methods preserve foreign refusal or original index sentinel");
    mwx_scene_quickjs_owner_discard_layer_mutations(consumer);
    mwx_scene_quickjs_owner_destroy(producer);
    run(consumer, 92, 3, "retired", MWX_SCENE_QUICKJS_OK, NULL,
        "all retained namespace methods remain safe after creator retirement");
    mwx_scene_quickjs_owner_destroy(consumer);
    consumer = at(d, source, 17, 93, 0);
    run(consumer, 93, 4, "replacement", MWX_SCENE_QUICKJS_OK, NULL,
        "replacement owner of the same layer does not acquire retired namespace identity");
    mwx_scene_quickjs_owner_destroy(consumer);
    mwx_scene_quickjs_domain_destroy(d);
}

static MWXSceneQuickJSLayerRecord *named_dynamic(MWXSceneQuickJSDomain *d, const char *name) {
    for (uint32_t index = d->authored_layer_count; index < d->layer_count; ++index)
        if (d->layers[index].configured && d->layers[index].name &&
            strcmp(d->layers[index].name, name) == 0) return &d->layers[index];
    return NULL;
}

static void dynamic_slot_reuse_and_retained_media(void) {
    MWXSceneQuickJSDomain *d = domain();
    MWXSceneQuickJSOwner *o = at(d,
        "let current;export function update(v){"
        "if(v==='create'||v==='replace'){current=thisScene.createLayer({name:v,text:'live'});"
        "if(!current)throw Error('birth refused');}"
        "if(v==='capture'){shared.old=current;shared.id=current.id;"
        "const p=Object.getOwnPropertyDescriptor(current,'text');shared.get=p.get;shared.set=p.set;"
        "shared.parent=current.getParent;shared.video=current.getVideoTexture();"
        "shared.texture=current.getTextureAnimation();shared.play=current.play;"
        "shared.video.addEndedCallback(()=>{shared.ended=true;});}"
        "if(v==='destroy')thisScene.destroyLayer(current);"
        "if(v==='verify'){const attempts=[()=>shared.old.text,()=>shared.old.alpha=0.2,"
        "()=>shared.get.call({}),()=>shared.set.call({},'wrong'),()=>shared.parent(),"
        "()=>shared.old.getVideoTexture(),()=>shared.old.getTextureAnimation(),"
        "()=>shared.play(),()=>shared.video.play(),()=>shared.video.rate,"
        "()=>shared.texture.play(),()=>shared.texture.rate];"
        "for(const attempt of attempts){let stale=false;try{attempt();}catch(e){stale=e instanceof TypeError;}"
        "if(!stale)throw Error('recycled attachment accepted');}"
        "if(current.id>=shared.id||current.text!=='live'||shared.ended)throw Error('new incarnation changed');}"
        "return v;}", 17, 91, 0);
    run(o, 91, 1, "create", MWX_SCENE_QUICKJS_OK, NULL, "dynamic media carrier creates");
    mwx_scene_quickjs_owner_commit_layer_mutations(o);
    MWXSceneQuickJSLayerRecord *old = named_dynamic(d, "create");
    check(old != NULL, "dynamic carrier is in original record store");
    if (old == NULL) return;
    const uint32_t slot = (uint32_t)(old - d->layers);
    const int64_t old_id = old->layer_id;
    // Inject provider observations to test handle identity, without adding a
    // video/animation constructor or a media backend to this VM fixture.
    MWXSceneQuickJSVideoObservation video = {.rate=1, .available=1, .source_incarnation={11,22}};
    publish_video_observation(d, &video, UINT32_MAX, false);
    old->video_source_index = 0;
    old->texture_animation_available = old->sound_available = true;
    old->texture_animation_rate = 1;
    run(o, 91, 2, "capture", MWX_SCENE_QUICKJS_OK, NULL, "native media references retain concrete identity");
    mwx_scene_quickjs_owner_commit_layer_mutations(o);
    run(o, 91, 3, "destroy", MWX_SCENE_QUICKJS_OK, NULL, "dynamic carrier retires");
    mwx_scene_quickjs_owner_commit_layer_mutations(o);
    check(!d->layers[slot].configured && d->free_dynamic_layer_head == slot,
        "retained JS and media handles do not pin a retired C slot");
    run(o, 91, 4, "replace", MWX_SCENE_QUICKJS_OK, NULL, "replacement reuses storage");
    mwx_scene_quickjs_owner_commit_layer_mutations(o);
    MWXSceneQuickJSLayerRecord *replacement = named_dynamic(d, "replace");
    check(replacement == &d->layers[slot] && replacement->layer_id < old_id,
        "same slot carries a different logical layer identity");
    if (replacement == NULL) return;
    video.source_incarnation[0] = 33; video.source_incarnation[1] = 44; video.ended_generation = 1;
    publish_video_observation(d, &video, UINT32_MAX, false);
    replacement->video_source_index = 0;
    replacement->texture_animation_available = replacement->sound_available = true;
    replacement->texture_animation_rate = 1;
    mwx_scene_quickjs_begin_callback(o);
    check(mwx_scene_quickjs_dispatch_video_ended_callbacks(o, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "retired EOF registration cannot observe replacement generation");
    mwx_scene_quickjs_end_callback(o);
    run(o, 91, 5, "verify", MWX_SCENE_QUICKJS_OK, NULL, "all retained native projections reject ABA");
    check(mwx_scene_quickjs_owner_media_playback_command_count(o) == 0 &&
        mwx_scene_quickjs_owner_texture_animation_command_count(o) == 0,
        "stale media references stage no command for replacement");
    mwx_scene_quickjs_owner_discard_layer_mutations(o);
    check(mwx_scene_quickjs_owner_remove_dynamic_layers(o), "permanent owner removal releases live slot");
    mwx_scene_quickjs_owner_destroy(o);
    mwx_scene_quickjs_domain_destroy(d);
}

static void withdrawn_video_cannot_revive_after_rollback(void) {
    MWXSceneQuickJSDomain *d = domain();
    MWXSceneQuickJSVideoObservation video = {.duration=10, .rate=1, .current_time=2,
        .loop=1, .is_playing=1, .available=1, .source_incarnation={11,22}};
    publish_video_observation(d, &video, 0, false);
    const char *source =
        "let held,escaped,fresh,oldEnded=0,newEnded=0;"
        "function stale(video){let failed=false;try{video.play();}catch(e){failed=e instanceof TypeError;}"
        "if(!failed)throw Error('withdrawn handle revived');}"
        "export function update(v){const layer=thisScene.getLayer('Caption');"
        "if(v==='old'){held=layer.getVideoTexture();held.addEndedCallback(()=>oldEnded++);}"
        "if(v==='escape'){escaped=layer.getVideoTexture();escaped.play();}"
        "if(v==='withdrawn'){stale(held);stale(escaped);"
        "if(layer.getVideoTexture()!==undefined||oldEnded!==0)throw Error('withdrawal rollback revived EOF');}"
        "if(v==='fresh'){stale(held);stale(escaped);fresh=layer.getVideoTexture();"
        "if(fresh.getCurrentTime()!==4||oldEnded!==0)throw Error('new observation');fresh.addEndedCallback(()=>newEnded++);}"
        "if(v==='ended'){if(oldEnded!==0||newEnded!==1)throw Error('old EOF callback transferred');fresh.play();}return v;}";
    MWXSceneQuickJSOwner *o = at(d, source, 17, 94, 0);
    run(o, 94, 0, "old", MWX_SCENE_QUICKJS_OK, NULL, "authored source handle and EOF register");
    mwx_scene_quickjs_owner_commit_layer_mutations(o);
    video.source_incarnation[0] = 33; video.source_incarnation[1] = 44;
    video.current_time = 7; video.ended_generation = 1;
    publish_video_observation(d, &video, 0, true);
    run(o, 94, 1, "escape", MWX_SCENE_QUICKJS_OK, NULL, "pending replacement emits its own source identity");
    MWXSceneQuickJSMediaPlaybackCommand escaped = {0};
    check(mwx_scene_quickjs_owner_media_playback_command_at(o, 0, &escaped, diagnostic, sizeof(diagnostic))
        == MWX_SCENE_QUICKJS_OK && escaped.video_source_incarnation[0] == 33
        && escaped.video_source_incarnation[1] == 44, "typed command preserves the pending source incarnation");
    mwx_scene_quickjs_owner_commit_layer_mutations(o);
    check(mwx_scene_quickjs_domain_withdraw_authored_video_sources(d) == MWX_SCENE_QUICKJS_OK,
        "rebuild withdraws current and rollback consumers");
    check(mwx_scene_quickjs_domain_rollback_layer_snapshot(d), "pending source values roll back");
    check(d->layers[0].video_source_index == UINT32_MAX && d->video_observations[0].source_incarnation[0] == 11,
        "rollback restores source values while the consumer stays withdrawn");
    video.source_incarnation[0] = 11; video.source_incarnation[1] = 22;
    video.current_time = 2;
    publish_video_observation(d, &video, UINT32_MAX, false);
    run(o, 94, 2, "withdrawn", MWX_SCENE_QUICKJS_OK, NULL, "late old-source EOF cannot revive withdrawn consumer");
    mwx_scene_quickjs_owner_commit_layer_mutations(o);
    check(escaped.video_source_incarnation[0] == 33 && escaped.video_source_incarnation[1] == 44,
        "rollback never rewrites an already exported command identity");
    video.source_incarnation[0] = 55; video.source_incarnation[1] = 66;
    video.current_time = 4; video.ended_generation = 2;
    publish_video_observation(d, &video, 0, false);
    run(o, 94, 3, "fresh", MWX_SCENE_QUICKJS_OK, NULL, "newly published consumer acquires a fresh video handle");
    mwx_scene_quickjs_owner_commit_layer_mutations(o);
    video.ended_generation = 3;
    publish_video_observation(d, &video, UINT32_MAX, false);
    run(o, 94, 4, "ended", MWX_SCENE_QUICKJS_OK, NULL, "only fresh source EOF callback delivers");
    mwx_scene_quickjs_owner_commit_layer_mutations(o);
    mwx_scene_quickjs_owner_destroy(o); mwx_scene_quickjs_domain_destroy(d);
}

static void failed_newborn_and_peer_journal(void) {
    MWXSceneQuickJSDomain *d = domain();
    MWXSceneQuickJSOwner *a = at(d,
        "let live;export function update(v){"
        "if(v==='seed')live=thisScene.createLayer({name:'original',text:'old'});"
        "if(v==='candidate'){thisScene.destroyLayer(live);"
        "shared.candidate=thisScene.createLayer({name:'candidate',text:'new'});}"
        "if(v==='verify'){for(const x of [shared.failed,shared.candidate]){let stale=false;"
        "try{x.text='wrong';}catch(e){stale=e instanceof TypeError;}if(!stale)throw Error('failed handle revived');}"
        "if(live.text!=='old')throw Error('previous current lost');}return v;}", 17, 91, 0);
    MWXSceneQuickJSOwner *b = at(d,
        "export function update(v){if(v!=='hold')thisScene.createLayer({name:'healthy',text:'peer'});return v;}", 42, 92, 0);
    MWXSceneQuickJSOwner *rejected = at(d,
        "export function update(v){shared.failed=thisScene.createLayer({name:'failed',text:'lost'});"
        "throw Error('failed birth');}", 17, 93, 0);
    run(a, 91, 1, "seed", MWX_SCENE_QUICKJS_OK, NULL, "existing dynamic instance commits");
    mwx_scene_quickjs_owner_commit_layer_mutations(a);
    run(b, 92, 2, "peer", MWX_SCENE_QUICKJS_OK, NULL, "peer holds shared journal");
    run(rejected, 93, 2, "fail", MWX_SCENE_QUICKJS_EXCEPTION, "failed birth", "failed newborn is withdrawn");
    MWXSceneQuickJSLayerRecord *failed = named_dynamic(d, "failed");
    check(failed && failed->destroyed && d->free_dynamic_layer_head == UINT32_MAX,
        "failed newborn slot remains quarantined while peer holds indices");
    const int64_t failed_id = failed ? failed->layer_id : 0;
    const uint32_t failed_slot = failed ? (uint32_t)(failed - d->layers) : UINT32_MAX;
    run(a, 91, 3, "candidate", MWX_SCENE_QUICKJS_OK, NULL, "same owner can make a later candidate");
    MWXSceneQuickJSLayerRecord *candidate = named_dynamic(d, "candidate");
    check(candidate && candidate != failed && candidate->layer_id < failed_id,
        "failed birth neither returns its logical ID nor its provisional slot");
    mwx_scene_quickjs_owner_discard_layer_mutations(a);
    mwx_scene_quickjs_owner_commit_layer_mutations(b);
    check(failed_slot < d->layer_count && !d->layers[failed_slot].configured &&
        named_dynamic(d, "candidate") == NULL && named_dynamic(d, "healthy") != NULL &&
        named_dynamic(d, "original") != NULL && !d->dynamic_layer_topology_transaction_active,
        "late rejection restores previous current and commits healthy peer");
    run(a, 91, 4, "verify", MWX_SCENE_QUICKJS_OK, NULL, "retained rejected handles stay stale");
    mwx_scene_quickjs_owner_discard_layer_mutations(a);
    run(b, 92, 5, "hold", MWX_SCENE_QUICKJS_OK, NULL, "value-only peer retains its callback journal");
    run(a, 91, 5, "candidate", MWX_SCENE_QUICKJS_OK, NULL, "healthy replacement waits for every participant");
    mwx_scene_quickjs_owner_commit_layer_mutations(a);
    check(named_dynamic(d, "original") && named_dynamic(d, "original")->destroyed &&
        d->dynamic_layer_topology_participant_count == 0 &&
        d->dynamic_layer_transaction_participant_count == 1,
        "a non-topology peer also prevents slot reclamation");
    mwx_scene_quickjs_owner_commit_layer_mutations(b);
    check(named_dynamic(d, "original") == NULL, "last value participant releases settled indices");
    check(mwx_scene_quickjs_owner_remove_dynamic_layers(a), "first owner teardown releases only its records");
    check(named_dynamic(d, "healthy") != NULL, "peer survives unrelated owner teardown");
    check(mwx_scene_quickjs_owner_remove_dynamic_layers(b), "peer teardown releases its records");
    mwx_scene_quickjs_owner_destroy(a); mwx_scene_quickjs_owner_destroy(b);
    mwx_scene_quickjs_owner_destroy(rejected);
    mwx_scene_quickjs_domain_destroy(d);
}

static void stage_snapshot(MWXSceneQuickJSDomain *d, uint64_t generation, bool retire_peer) {
    const double one[3] = {1, 1, 1}, zero[3] = {0, 0, 0};
    check(mwx_scene_quickjs_domain_begin_layer_snapshot(d, generation, 0,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "shared snapshot begins");
    for (uint32_t index = 0; index < d->authored_layer_count; ++index)
        check(mwx_scene_quickjs_domain_update_layer_runtime_fields(d, index,
            one, zero, retire_peer && index == 1, 1, 1, 0, 1, "seed", 4, "", 0, 12, one,
            diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "authored snapshot stages");
}

static void snapshot_and_newborn_retirement(void) {
    MWXSceneQuickJSDomain *d = domain();
    MWXSceneQuickJSOwner *o = at(d,
        "let live;export function update(v){"
        "if(v==='seed')live=thisScene.createLayer({name:'original',text:'old'});"
        "if(v==='replace'){thisScene.destroyLayer(live);thisScene.createLayer({name:'pending',text:'new'});}"
        "if(v==='ephemeral'){const born=thisScene.createLayer({name:'ephemeral',text:'gone'});born.text='updated';thisScene.destroyLayer(born);}"
        "if(v==='pair'){thisScene.createLayer({name:'left',text:'l'});thisScene.createLayer({name:'right',text:'r'});}"
        "return v;}", 17, 91, 0);
    run(o, 91, 1, "seed", MWX_SCENE_QUICKJS_OK, NULL, "rollback baseline owns a live dynamic record");
    mwx_scene_quickjs_owner_commit_layer_mutations(o);
    stage_snapshot(d, 1, true);
    check(mwx_scene_quickjs_domain_commit_layer_snapshot(d, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "snapshot with dynamic order baseline commits provisionally");
    check(d->rollback_layer_order != NULL, "real rollback order retains dynamic indices");
    run(o, 91, 2, "replace", MWX_SCENE_QUICKJS_OK, NULL, "replacement remains provisional");
    mwx_scene_quickjs_owner_discard_layer_mutations(o);
    MWXSceneQuickJSLayerRecord *pending = named_dynamic(d, "pending");
    check(pending && pending->destroyed && d->free_dynamic_layer_head == UINT32_MAX,
        "owner discard cannot recycle snapshot-owned indices");
    check(mwx_scene_quickjs_domain_rollback_layer_snapshot(d), "shared rollback completes");
    check(named_dynamic(d, "pending") == NULL && named_dynamic(d, "original") != NULL &&
        !d->layers[1].destroyed && !d->dynamic_layer_topology_transaction_active,
        "rollback restores old layer/order and releases only the rejected birth");
    stage_snapshot(d, 2, false);
    run(o, 91, 3, "ephemeral", MWX_SCENE_QUICKJS_OK, NULL, "newborn is destroyed in its birth callback");
    MWXSceneQuickJSLayerMutation birth = {0};
    check(mwx_scene_quickjs_owner_layer_mutation_count(o) == 1 &&
        mwx_scene_quickjs_owner_layer_mutation_at(o, 0, &birth, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK &&
        birth.kind == MWX_SCENE_QUICKJS_LAYER_MUTATION_DESTROY && birth.dynamic == 1 &&
        birth.fields == MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_CREATED && strcmp(birth.text, "updated") == 0,
        "net-zero mutation exports its birth without obsolete attribute writes");
    mwx_scene_quickjs_owner_commit_layer_mutations(o);
    MWXSceneQuickJSLayerRecord *retired = named_dynamic(d, "ephemeral");
    check(retired != NULL &&
        !mwx_scene_quickjs_owner_remove_dynamic_layers(o), "pending snapshot holds retirement and owner teardown");
    check(retired != NULL && retired->dirty_fields == 0,
        "committed birth fact does not survive into a later callback");
    const uint32_t retired_slot = retired == NULL ? UINT32_MAX : (uint32_t)(retired - d->layers);
    mwx_scene_quickjs_domain_abort_layer_snapshot(d);
    check(named_dynamic(d, "ephemeral") == NULL, "snapshot abort releases the settled tombstone");
    run(o, 91, 4, "pair", MWX_SCENE_QUICKJS_OK, NULL, "free list admits two distinct live instances");
    check(retired_slot < d->layer_count && named_dynamic(d, "left") == &d->layers[retired_slot] &&
        d->layers[retired_slot].layer_id != birth.layer_id &&
        (d->layers[retired_slot].dirty_fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_CREATED) != 0,
        "recycled physical slot exports a fresh birth for a different logical identity");
    mwx_scene_quickjs_owner_commit_layer_mutations(o);
    check(named_dynamic(d, "left") && named_dynamic(d, "right") &&
        named_dynamic(d, "left") != named_dynamic(d, "right"),
        "repeated CREATE/DESTROY journal indices enter free list exactly once");
    check(mwx_scene_quickjs_owner_remove_dynamic_layers(o), "owner teardown succeeds after snapshot exits");
    mwx_scene_quickjs_owner_destroy(o); mwx_scene_quickjs_domain_destroy(d);
}

static void sustained_dynamic_slot_lifetime(void) {
    first_layer_id = -1; second_layer_id = -9;
    MWXSceneQuickJSDomain *d = domain();
    MWXSceneQuickJSOwner *o = at(d,
        "let live,first,previous=0;export function update(v){"
        "if(live)thisScene.destroyLayer(live);"
        "live=thisScene.createLayer({name:'cycled',text:'live'});"
        "if(!live||live.id>=previous||live.id>=-9)throw Error('identity/lifetime failure');"
        "previous=live.id;if(!first)first=live;else{let stale=false;try{first.text;}"
        "catch(e){stale=e instanceof TypeError;}if(!stale)throw Error('retained birth revived');}return v;}", -1, 91, 0);
    unsigned completed = 0;
    for (; completed < 5000; ++completed) {
        MWXSceneQuickJSFrameInput frame = {.frame_time = 0.016, .runtime = completed};
        char output[8]; size_t length = 0;
        MWXSceneQuickJSResult result = mwx_scene_quickjs_owner_update_string(o, 91,
            "cycle", 5, &frame, "", 0, "{}", 2, output, sizeof(output), &length,
            diagnostic, sizeof(diagnostic));
        if (result != MWX_SCENE_QUICKJS_OK || length != 5 || memcmp(output, "cycle", 5)) break;
        mwx_scene_quickjs_owner_commit_layer_mutations(o);
    }
    check(completed == 5000, "more than 4096 births survive retained old JS references");
    check(d->layer_count == d->authored_layer_count + 2 &&
        mwx_scene_quickjs_layer_active_count(d) == 3 && d->next_dynamic_layer_id == -5010,
        "native high-water is constant and IDs skip all prepared authored identities");
    check(mwx_scene_quickjs_owner_remove_dynamic_layers(o), "sustained instance teardown is terminal");
    mwx_scene_quickjs_owner_destroy(o); mwx_scene_quickjs_domain_destroy(d);
    first_layer_id = 17; second_layer_id = 42;
}

static void failed_handle_construction(void) {
    MWXSceneQuickJSDomain *d = domain();
    MWXSceneQuickJSOwner *o = at(d,
        "export function update(v){let caught=false;try{thisScene.createLayer({name:'cancelled',text:'lost'});}"
        "catch(e){caught=true;}if(!caught)throw Error('allocation succeeded');"
        "if(!thisScene.createLayer({name:'survivor',text:'live'}))throw Error('healthy birth refused');return v;}",
        17, 91, 0);
    fail_layer_reference_allocation = 1;
    run(o, 91, 1, "fault", MWX_SCENE_QUICKJS_OK, NULL, "caught native handle allocation failure preserves healthy birth");
    check(named_dynamic(d, "cancelled") && named_dynamic(d, "cancelled")->destroyed &&
        named_dynamic(d, "survivor") && mwx_scene_quickjs_owner_layer_mutation_count(o) == 1,
        "failed constructor keeps its identity quarantined without publishing a mutation");
    mwx_scene_quickjs_owner_commit_layer_mutations(o);
    check(named_dynamic(d, "cancelled") == NULL && named_dynamic(d, "survivor") &&
        mwx_scene_quickjs_layer_active_count(d) == 3,
        "committing a caught failure cannot replay its withdrawn CREATE");
    check(mwx_scene_quickjs_owner_remove_dynamic_layers(o), "constructor fault leaves teardown complete");
    mwx_scene_quickjs_owner_destroy(o); mwx_scene_quickjs_domain_destroy(d);
}

int main(void) {
    shared_lookup_case("thisScene.getLayer('Caption')", "shared.ref.text=v", 17, 0);
    shared_lookup_case("thisLayer", "shared.ref.text=v", 17, 0);
    shared_lookup_case("thisObject", "const alias=shared.ref;alias['text']=v", 17, 0);
    shared_lookup_case("thisScene.getLayerByID('17')", "const alias=shared.ref;alias['text']=v", 17, 0);
    shared_lookup_case("thisScene.getLayer(0)", "Object.assign(shared.ref,{text:v})", 17, 0);
    shared_lookup_case("thisScene.getLayer('Peer')", "shared.ref.text=v", 42, 0);
    shared_lookup_case("thisScene.getLayer('Caption')", "shared.ref.text=v", 17, 1);
    first_layer_name = "Headline"; second_layer_name = "Body";
    shared_lookup_case("thisScene.getLayer('Headline')", "let renamed=shared.ref;renamed.text=String(v)", 17, 0);
    first_layer_name = "Caption"; second_layer_name = "Peer";
    protected_receiver_and_generation();
    protected_dynamic_and_atomicity();
    value_only_capabilities();
    publication_and_retirement();
    owner_receiver_metadata();
    owner_without_layer_catalog();
    attached_capabilities_remain_owner_bound();
    retired_owner_attachments();
    namespace_rejection_and_recovery();
    shared_basic_fields();
    namespace_method_table();
    dynamic_slot_reuse_and_retained_media();
    withdrawn_video_cannot_revive_after_rollback();
    failed_newborn_and_peer_journal();
    snapshot_and_newborn_retirement();
    sustained_dynamic_slot_lifetime();
    failed_handle_construction();
    printf("{\"checks\":%d,\"failures\":%d}\n", checks, failures);
    return failures ? 1 : 0;
}
