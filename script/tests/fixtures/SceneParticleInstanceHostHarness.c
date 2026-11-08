#include "SceneQuickJS.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char diagnostic[512];
static int failures;
static const double zero[3] = {0, 0, 0}, one[3] = {1, 1, 1}, extent[2] = {16, 16};
static uint32_t layer_count;

static void check(int condition, const char *label) {
    if (!condition) { fprintf(stderr, "FAIL %s: %s\n", label, diagnostic); ++failures; }
}

static void publish(MWXSceneQuickJSDomain *domain, uint64_t generation,
                    int unavailable, int destroyed, double alpha, double rate, double count, int finalize) {
    check(mwx_scene_quickjs_domain_begin_layer_snapshot(domain, generation, 0,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "begin snapshot");
    for (uint32_t i = 0; i < layer_count; ++i) {
        check(mwx_scene_quickjs_domain_update_layer_runtime_fields(domain, i,
            one, zero, i == destroyed, 1, 1, 0, .6, "", 0, "", 0, 32, one,
            diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "runtime fields");
        check(mwx_scene_quickjs_domain_update_layer_particle_instance(domain, i,
            i != unavailable, alpha, rate, count, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
            "instance projection");
        // The second layer deliberately lacks playback admission but has an instance.
        MWXSceneQuickJSParticlePlaybackState playback = {.available = i == 0};
        check(mwx_scene_quickjs_domain_update_layer_particle_playback(domain, i,
            playback, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "playback projection");
    }
    check(mwx_scene_quickjs_domain_commit_layer_snapshot(domain, diagnostic,
        sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "commit snapshot");
    if (finalize) mwx_scene_quickjs_domain_finalize_layer_snapshot(domain);
}

static MWXSceneQuickJSDomain *make_domain(uint32_t count) {
    layer_count = count;
    MWXSceneQuickJSDomain *domain = mwx_scene_quickjs_domain_create(
        32 * 1024 * 1024, 512 * 1024, 1000000, diagnostic, sizeof(diagnostic));
    check(domain != NULL, "domain");
    if (domain == NULL) return NULL;
    check(mwx_scene_quickjs_domain_configure_layer_catalog(domain, count, 0,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "catalog");
    for (uint32_t i = 0; i < count; ++i) {
        char name[32]; snprintf(name, sizeof(name), "particle%u", i);
        check(mwx_scene_quickjs_domain_set_layer_runtime_descriptor(domain, i,
            42 + i, 0, 0, name, strlen(name), zero, extent, one, zero, 1, .6,
            "", 0, "", 0, 32, one, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
            "descriptor");
    }
    publish(domain, 1, -1, -1, 1, 1, 1, 1);
    return domain;
}

static MWXSceneQuickJSOwner *make_owner(MWXSceneQuickJSDomain *domain, const char *source) {
    MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_owner_create(domain, source,
        strlen(source), 7, diagnostic, sizeof(diagnostic));
    check(owner != NULL, "owner");
    if (owner != NULL)
        check(mwx_scene_quickjs_owner_configure_layer_identity(owner, 42,
            diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "owner identity");
    return owner;
}

static MWXSceneQuickJSResult update(MWXSceneQuickJSOwner *owner, uint64_t generation,
                                   double input, double *output) {
    MWXSceneQuickJSFrameInput frame = {.frame_time = 1.0 / 60.0, .runtime = 2};
    return mwx_scene_quickjs_owner_update_scalar(owner, generation, input, &frame,
        output, diagnostic, sizeof(diagnostic));
}

static void test_access(MWXSceneQuickJSDomain *domain) {
    MWXSceneQuickJSOwner *owner = make_owner(domain,
        "export function update(v){"
        "const instance=thisLayer.instance;"
        "if(instance.alpha!==1||instance.rate!==1||instance.count!==1||thisLayer.alpha!==.6)throw Error('defaults');"
        "instance.alpha=.25;instance.rate=1/2;instance.count=1+1;"
        "if(thisScene.getLayer('particle0').instance.alpha!==.25)throw Error('name');"
        "thisScene.getLayer(0).instance.alpha=.75;"
        "const peer=thisScene.getLayer('particle1').instance;"
        "peer.alpha=.4;peer.rate=2;peer.count=.5;"
        "if(thisScene.getLayer(1).instance.alpha!==.4||peer.rate!==2||peer.count!==.5)throw Error('second');"
        "if(instance.rate!==.5||instance.count!==2)throw Error('independent fields');"
        "return thisLayer.instance.alpha;}" );
    if (owner == NULL) return;
    double output;
    check(update(owner, 7, 0, &output) == MWX_SCENE_QUICKJS_OK && output == .75,
        "thisLayer/name/index share same callback overlay");
    check(mwx_scene_quickjs_owner_layer_mutation_count(owner) == 2, "coalesced journal");
    MWXSceneQuickJSLayerMutation mutation;
    check(mwx_scene_quickjs_owner_layer_mutation_at(owner, 0, &mutation,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK &&
        mutation.fields == (MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PARTICLE_ALPHA |
            MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PARTICLE_RATE |
            MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PARTICLE_COUNT) &&
        mutation.particle_alpha == .75 && mutation.particle_rate == .5 && mutation.particle_count == 2 &&
        mutation.alpha == .6, "independent instance scalar ABI");
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    mwx_scene_quickjs_owner_destroy(owner);
}

static void test_invalid(MWXSceneQuickJSDomain *domain) {
    MWXSceneQuickJSOwner *owner = make_owner(domain,
        "export function update(v){let caught=0;"
        "for(const field of ['alpha','rate','count'])for(const x of [true,'0.25',null,{},NaN,Infinity,-Infinity]){"
        "try{thisLayer.instance[field]=x;}catch(e){++caught;}}"
        "try{thisLayer.instance={alpha:.5};}catch(e){++caught;}"
        "try{thisLayer.instance.unknownScalar=2;}catch(e){++caught;}"
        "if(caught!==23||thisLayer.instance.alpha!==1||thisLayer.instance.rate!==1||thisLayer.instance.count!==1)throw Error('invalid accepted');"
        "for(const field of ['alpha','rate','count']){thisLayer.instance[field]=-2;thisLayer.instance[field]=3;}"
        "if(thisLayer.instance.rate!==3||thisLayer.instance.count!==3)throw Error('finite range');"
        "return thisLayer.instance.alpha;}" );
    if (owner == NULL) return;
    double output;
    check(update(owner, 7, 0, &output) == MWX_SCENE_QUICKJS_OK && output == 3,
        "finite Number contract, immutable accessor and unsupported fields");
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    mwx_scene_quickjs_owner_destroy(owner);
    check(mwx_scene_quickjs_domain_begin_layer_snapshot(domain, 2, 0,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "begin invalid projection");
    for (size_t field = 0; field < 3; ++field) {
        double values[3] = {1, 1, 1}; values[field] = NAN;
        check(mwx_scene_quickjs_domain_update_layer_particle_instance(domain, 0, 1,
            values[0], values[1], values[2], diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
            "publication rejects nonfinite instance input");
    }
    mwx_scene_quickjs_domain_abort_layer_snapshot(domain);
    publish(domain, 2, 1, -1, 1, 1, 1, 1);
    owner = make_owner(domain, "export function update(v){thisScene.getLayer(1).instance.alpha=.2;return v;}");
    if (owner != NULL) {
        check(update(owner, 7, 0, &output) != MWX_SCENE_QUICKJS_OK &&
            mwx_scene_quickjs_owner_layer_mutation_count(owner) == 0, "unavailable nonparticle projection");
        mwx_scene_quickjs_owner_destroy(owner);
    }
}

static void test_rollback(MWXSceneQuickJSDomain *domain) {
    MWXSceneQuickJSOwner *owner = make_owner(domain,
        "export function update(v){if(v===0){thisLayer.instance.alpha=.25;thisLayer.instance.rate=2;"
        "thisLayer.instance.count=.5;throw Error('rollback');}"
        "return thisLayer.instance.alpha;}" );
    if (owner == NULL) return;
    double output;
    check(update(owner, 7, 0, &output) != MWX_SCENE_QUICKJS_OK &&
        mwx_scene_quickjs_owner_layer_mutation_count(owner) == 0, "throw clears journal");
    check(update(owner, 7, 1, &output) == MWX_SCENE_QUICKJS_DISABLED,
        "throw owner remains disabled");
    mwx_scene_quickjs_owner_destroy(owner);
    owner = make_owner(domain, "export function update(v){return v===10?thisLayer.instance.rate:"
        "v===11?thisLayer.instance.count:thisLayer.instance.alpha;}");
    if (owner == NULL) return;
    check(update(owner, 7, 1, &output) == MWX_SCENE_QUICKJS_OK && output == 1,
        "healthy peer sees unchanged committed projection");
    check(update(owner, 7, 10, &output) == MWX_SCENE_QUICKJS_OK && output == 1,
        "failed owner keeps peer rate");
    check(update(owner, 7, 11, &output) == MWX_SCENE_QUICKJS_OK && output == 1,
        "failed owner keeps peer count");
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    const uint32_t fields = MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PARTICLE_ALPHA |
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PARTICLE_RATE |
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PARTICLE_COUNT;
    for (size_t field = 0; field < 3; ++field) {
        double values[3] = {1, 1, 1}; values[field] = NAN;
        check(mwx_scene_quickjs_owner_add_authored_layer_mutation_baseline(owner, 7, 42,
            fields, zero, one, zero, 1, 1, 0, "", 0, "", 0, .6,
            values[0], values[1], values[2], 0, 32, one, 0, NULL, diagnostic, sizeof(diagnostic))
            == MWX_SCENE_QUICKJS_INVALID_ARGUMENT, "baseline rejects nonfinite instance input");
    }
    check(mwx_scene_quickjs_owner_add_authored_layer_mutation_baseline(owner, 7, 42,
        fields, zero, one, zero, 1, 1, 0,
        "", 0, "", 0, .6, .33, .5, 2, 0, 32, one, 0, NULL, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "cursor baseline accepted");
    check(update(owner, 7, 1, &output) == MWX_SCENE_QUICKJS_OK && output == .33, "baseline projection");
    check(update(owner, 7, 10, &output) == MWX_SCENE_QUICKJS_OK && output == .5, "baseline rate projection");
    check(update(owner, 7, 11, &output) == MWX_SCENE_QUICKJS_OK && output == 2, "baseline count projection");
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    mwx_scene_quickjs_owner_clear_authored_layer_mutation_baselines(owner);
    check(update(owner, 6, 1, &output) == MWX_SCENE_QUICKJS_STALE_OWNER, "old owner generation");
    mwx_scene_quickjs_owner_destroy(owner);
}

static void test_snapshot(MWXSceneQuickJSDomain *domain) {
    MWXSceneQuickJSOwner *owner = make_owner(domain,
        "let saved;export function update(v){if(!saved)saved=thisLayer.instance;"
        "return v===1?saved.rate:v===2?saved.count:saved.alpha;}" );
    if (owner == NULL) return;
    double output;
    publish(domain, 2, -1, -1, .4, .5, 2, 0);
    check(update(owner, 7, 0, &output) == MWX_SCENE_QUICKJS_OK && output == .4, "committed projection");
    check(update(owner, 7, 1, &output) == MWX_SCENE_QUICKJS_OK && output == .5, "committed rate projection");
    check(update(owner, 7, 2, &output) == MWX_SCENE_QUICKJS_OK && output == 2, "committed count projection");
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    check(mwx_scene_quickjs_domain_rollback_layer_snapshot(domain), "snapshot rollback");
    check(update(owner, 7, 0, &output) == MWX_SCENE_QUICKJS_OK && output == 1, "rollback restores instance");
    check(update(owner, 7, 1, &output) == MWX_SCENE_QUICKJS_OK && output == 1, "rollback restores rate");
    check(update(owner, 7, 2, &output) == MWX_SCENE_QUICKJS_OK && output == 1, "rollback restores count");
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    publish(domain, 3, -1, -1, .4, .5, 2, 1);
    check(mwx_scene_quickjs_domain_begin_layer_snapshot(domain, 4, 0, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "begin reuse");
    for (uint32_t i = 0; i < layer_count; ++i)
        check(mwx_scene_quickjs_domain_reuse_layer_runtime_fields(domain, i,
            diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "reuse");
    check(mwx_scene_quickjs_domain_commit_layer_snapshot(domain, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "commit reuse");
    mwx_scene_quickjs_domain_finalize_layer_snapshot(domain);
    check(update(owner, 7, 0, &output) == MWX_SCENE_QUICKJS_OK && output == .4, "reuse preserves projection");
    check(update(owner, 7, 1, &output) == MWX_SCENE_QUICKJS_OK && output == .5, "reuse preserves rate");
    check(update(owner, 7, 2, &output) == MWX_SCENE_QUICKJS_OK && output == 2, "reuse preserves count");
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    publish(domain, 5, -1, 0, 1, 1, 1, 1);
    check(update(owner, 7, 0, &output) != MWX_SCENE_QUICKJS_OK, "cached destroyed instance rejects");
    mwx_scene_quickjs_owner_destroy(owner);
}

static void test_budget(MWXSceneQuickJSDomain *domain) {
    MWXSceneQuickJSOwner *owner = make_owner(domain,
        "export function update(v){let caught=0;for(let i=0;i<v;++i){"
        "try{const instance=thisScene.getLayer(i).instance;"
        "instance.alpha=.25;instance.rate=.5;instance.count=2;}catch(e){++caught;}}"
        "const first=thisScene.getLayer(0).instance;first.alpha=.5;first.count*=2;thisScene.getLayer(0).alpha=.75;"
        "return caught;}" );
    if (owner == NULL) return;
    double output;
    for (uint32_t extra = 0; extra <= 1; ++extra) {
        check(update(owner, 7, MWX_SCENE_QUICKJS_MAX_LAYERS + extra, &output) == MWX_SCENE_QUICKJS_OK &&
            output == extra && mwx_scene_quickjs_owner_layer_mutation_count(owner) == MWX_SCENE_QUICKJS_MAX_LAYERS,
            "full catalog and caught missing layer retain a complete journal");
        for (uint32_t index = 0; index < MWX_SCENE_QUICKJS_MAX_LAYERS; ++index) {
            MWXSceneQuickJSLayerMutation mutation;
            uint32_t fields = MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PARTICLE_ALPHA |
                MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PARTICLE_RATE |
                MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PARTICLE_COUNT;
            if (index == 0) fields |= MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ALPHA;
            check(mwx_scene_quickjs_owner_layer_mutation_at(owner, index, &mutation,
                diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK &&
                mutation.layer_id == 42 + index && mutation.fields == fields &&
                mutation.particle_alpha == (index == 0 ? .5 : .25) &&
                mutation.particle_rate == .5 && mutation.particle_count == (index == 0 ? 4 : 2) &&
                mutation.alpha == (index == 0 ? .75 : .6), "every valid target exports its final values");
        }
        mwx_scene_quickjs_owner_discard_layer_mutations(owner);
        check(mwx_scene_quickjs_owner_layer_mutation_count(owner) == 0, "discard clears the full catalog journal");
    }
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    check(update(owner, 7, 1, &output) == MWX_SCENE_QUICKJS_OK &&
        output == 0 && mwx_scene_quickjs_owner_layer_mutation_count(owner) == 1, "discard preserves owner reuse");
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    mwx_scene_quickjs_owner_destroy(owner);
}

static double prefix[2];
static size_t prefix_count;
static MWXSceneQuickJSResult emission(void *opaque, MWXSceneQuickJSOwner *owner,
    const MWXSceneQuickJSParticlePlaybackCommand *command, MWXSceneQuickJSParticlePlaybackState *projection) {
    (void)opaque;
    if (prefix_count >= 2) return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    MWXSceneQuickJSResult result = mwx_scene_quickjs_owner_particle_instance_alpha(
        owner, command->layer_id, &prefix[prefix_count]);
    if (result == MWX_SCENE_QUICKJS_OK) { ++prefix_count; projection->available = 1; }
    return result;
}

static void test_prefix(MWXSceneQuickJSDomain *domain) {
    MWXSceneQuickJSOwner *owner = make_owner(domain,
        "export function update(v){thisLayer.instance.alpha=.25;thisLayer.emitParticles(1);"
        "thisLayer.instance.alpha=.75;thisLayer.emitParticles(1);return v;}" );
    if (owner == NULL) return;
    mwx_scene_quickjs_domain_begin_particle_frame(domain, emission, NULL, NULL, 1000, 1024);
    double output;
    check(update(owner, 7, 0, &output) == MWX_SCENE_QUICKJS_OK &&
        prefix_count == 2 && prefix[0] == .25 && prefix[1] == .75, "emit captures each setter prefix");
    double alpha;
    check(mwx_scene_quickjs_owner_particle_instance_alpha(owner, 42, &alpha) == MWX_SCENE_QUICKJS_STALE_OWNER,
        "native getter unavailable outside callback");
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    mwx_scene_quickjs_domain_end_particle_frame(domain);
    mwx_scene_quickjs_owner_destroy(owner);
}

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    MWXSceneQuickJSDomain *domain = make_domain(strcmp(argv[1], "budget") == 0 ? MWX_SCENE_QUICKJS_MAX_LAYERS : 2);
    if (domain == NULL) return 1;
    if (strcmp(argv[1], "access") == 0) test_access(domain);
    else if (strcmp(argv[1], "invalid") == 0) test_invalid(domain);
    else if (strcmp(argv[1], "rollback") == 0) test_rollback(domain);
    else if (strcmp(argv[1], "snapshot") == 0) test_snapshot(domain);
    else if (strcmp(argv[1], "budget") == 0) test_budget(domain);
    else if (strcmp(argv[1], "prefix") == 0) test_prefix(domain);
    else ++failures;
    mwx_scene_quickjs_domain_destroy(domain);
    return failures == 0 ? 0 : 1;
}
