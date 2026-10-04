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
                    int unavailable, int destroyed, double alpha, int finalize) {
    check(mwx_scene_quickjs_domain_begin_layer_snapshot(domain, generation,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "begin snapshot");
    for (uint32_t i = 0; i < layer_count; ++i) {
        check(mwx_scene_quickjs_domain_update_layer_runtime_fields(domain, i,
            one, zero, i == destroyed, 1, 1, .6, "", 0, "", 0, 32, one,
            diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "runtime fields");
        check(mwx_scene_quickjs_domain_update_layer_particle_instance_alpha(domain, i,
            i != unavailable, alpha, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
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
    check(mwx_scene_quickjs_domain_configure_layer_catalog(domain, count,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "catalog");
    for (uint32_t i = 0; i < count; ++i) {
        char name[32]; snprintf(name, sizeof(name), "particle%u", i);
        check(mwx_scene_quickjs_domain_set_layer_runtime_descriptor(domain, i,
            42 + i, 0, 0, name, strlen(name), zero, extent, one, zero, 1, .6,
            "", 0, "", 0, 32, one, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
            "descriptor");
    }
    publish(domain, 1, -1, -1, 1, 1);
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
        "if(thisLayer.instance.alpha!==1||thisLayer.alpha!==.6)throw Error('defaults');"
        "thisLayer.instance.alpha=.25;"
        "if(thisScene.getLayer('particle0').instance.alpha!==.25)throw Error('name');"
        "thisScene.getLayer(0).instance.alpha=.75;"
        "thisScene.getLayer('particle1').instance.alpha=.4;"
        "if(thisScene.getLayer(1).instance.alpha!==.4)throw Error('second');"
        "return thisLayer.instance.alpha;}" );
    if (owner == NULL) return;
    double output;
    check(update(owner, 7, 0, &output) == MWX_SCENE_QUICKJS_OK && output == .75,
        "thisLayer/name/index share same callback overlay");
    check(mwx_scene_quickjs_owner_layer_mutation_count(owner) == 2, "coalesced journal");
    MWXSceneQuickJSLayerMutation mutation;
    check(mwx_scene_quickjs_owner_layer_mutation_at(owner, 0, &mutation,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK &&
        mutation.fields == MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PARTICLE_ALPHA &&
        mutation.particle_alpha == .75 && mutation.alpha == .6, "independent alpha ABI");
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    mwx_scene_quickjs_owner_destroy(owner);
}

static void test_invalid(MWXSceneQuickJSDomain *domain) {
    MWXSceneQuickJSOwner *owner = make_owner(domain,
        "export function update(v){let caught=0;"
        "for(const x of [true,'0.25',null,{},NaN,Infinity,-Infinity]){"
        "try{thisLayer.instance.alpha=x;}catch(e){++caught;}}"
        "try{thisLayer.instance={alpha:.5};}catch(e){++caught;}"
        "try{thisLayer.instance.rate=2;}catch(e){++caught;}"
        "if(caught!==9||thisLayer.instance.alpha!==1)throw Error('invalid accepted');"
        "thisLayer.instance.alpha=-2;thisLayer.instance.alpha=3;return thisLayer.instance.alpha;}" );
    if (owner == NULL) return;
    double output;
    check(update(owner, 7, 0, &output) == MWX_SCENE_QUICKJS_OK && output == 3,
        "finite Number contract, immutable accessor and unsupported fields");
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    mwx_scene_quickjs_owner_destroy(owner);
    publish(domain, 2, 1, -1, 1, 1);
    owner = make_owner(domain, "export function update(v){thisScene.getLayer(1).instance.alpha=.2;return v;}");
    if (owner != NULL) {
        check(update(owner, 7, 0, &output) != MWX_SCENE_QUICKJS_OK &&
            mwx_scene_quickjs_owner_layer_mutation_count(owner) == 0, "unavailable nonparticle projection");
        mwx_scene_quickjs_owner_destroy(owner);
    }
}

static void test_rollback(MWXSceneQuickJSDomain *domain) {
    MWXSceneQuickJSOwner *owner = make_owner(domain,
        "export function update(v){if(v===0){thisLayer.instance.alpha=.25;throw Error('rollback');}"
        "return thisLayer.instance.alpha;}" );
    if (owner == NULL) return;
    double output;
    check(update(owner, 7, 0, &output) != MWX_SCENE_QUICKJS_OK &&
        mwx_scene_quickjs_owner_layer_mutation_count(owner) == 0, "throw clears journal");
    check(update(owner, 7, 1, &output) == MWX_SCENE_QUICKJS_DISABLED,
        "throw owner remains disabled");
    mwx_scene_quickjs_owner_destroy(owner);
    owner = make_owner(domain, "export function update(v){return thisLayer.instance.alpha;}");
    if (owner == NULL) return;
    check(update(owner, 7, 1, &output) == MWX_SCENE_QUICKJS_OK && output == 1,
        "healthy peer sees unchanged committed projection");
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    check(mwx_scene_quickjs_owner_add_authored_layer_mutation_baseline(owner, 7, 42,
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PARTICLE_ALPHA, zero, one, zero, 1, 1,
        "", 0, "", 0, .6, .33, one, 0, NULL, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK,
        "cursor baseline accepted");
    check(update(owner, 7, 1, &output) == MWX_SCENE_QUICKJS_OK && output == .33, "baseline projection");
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    mwx_scene_quickjs_owner_clear_authored_layer_mutation_baselines(owner);
    check(update(owner, 6, 1, &output) == MWX_SCENE_QUICKJS_STALE_OWNER, "old owner generation");
    mwx_scene_quickjs_owner_destroy(owner);
}

static void test_snapshot(MWXSceneQuickJSDomain *domain) {
    MWXSceneQuickJSOwner *owner = make_owner(domain,
        "let saved;export function update(v){if(!saved)saved=thisLayer.instance;return saved.alpha;}" );
    if (owner == NULL) return;
    double output;
    publish(domain, 2, -1, -1, .4, 0);
    check(update(owner, 7, 0, &output) == MWX_SCENE_QUICKJS_OK && output == .4, "committed projection");
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    check(mwx_scene_quickjs_domain_rollback_layer_snapshot(domain), "snapshot rollback");
    check(update(owner, 7, 0, &output) == MWX_SCENE_QUICKJS_OK && output == 1, "rollback restores instance");
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    check(mwx_scene_quickjs_domain_begin_layer_snapshot(domain, 2, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "begin reuse");
    for (uint32_t i = 0; i < layer_count; ++i)
        check(mwx_scene_quickjs_domain_reuse_layer_runtime_fields(domain, i,
            diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "reuse");
    check(mwx_scene_quickjs_domain_commit_layer_snapshot(domain, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK, "commit reuse");
    mwx_scene_quickjs_domain_finalize_layer_snapshot(domain);
    check(update(owner, 7, 0, &output) == MWX_SCENE_QUICKJS_OK && output == 1, "reuse preserves projection");
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    publish(domain, 3, -1, 0, 1, 1);
    check(update(owner, 7, 0, &output) != MWX_SCENE_QUICKJS_OK, "cached destroyed instance rejects");
    mwx_scene_quickjs_owner_destroy(owner);
}

static void test_budget(MWXSceneQuickJSDomain *domain) {
    MWXSceneQuickJSOwner *owner = make_owner(domain,
        "export function update(v){for(let i=0;i<v;++i){"
        "try{thisScene.getLayer(i).instance.alpha=.25;}catch(e){}}return 1;}" );
    if (owner == NULL) return;
    double output;
    check(update(owner, 7, 256, &output) == MWX_SCENE_QUICKJS_OK &&
        mwx_scene_quickjs_owner_layer_mutation_count(owner) == 256, "exact journal budget");
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    check(update(owner, 7, 257, &output) == MWX_SCENE_QUICKJS_OK &&
        mwx_scene_quickjs_owner_layer_mutation_count(owner) == SIZE_MAX, "caught overflow stays unsafe");
    MWXSceneQuickJSLayerMutation mutation;
    check(mwx_scene_quickjs_owner_layer_mutation_at(owner, 0, &mutation,
        diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_MUTATION_OVERFLOW, "overflow cannot export partial journal");
    mwx_scene_quickjs_owner_discard_layer_mutations(owner);
    check(update(owner, 7, 1, &output) == MWX_SCENE_QUICKJS_OK &&
        mwx_scene_quickjs_owner_layer_mutation_count(owner) == 1, "discard recovers owner budget");
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
    MWXSceneQuickJSDomain *domain = make_domain(strcmp(argv[1], "budget") == 0 ? 257 : 2);
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
