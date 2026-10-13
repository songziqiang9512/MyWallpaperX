#include "SceneScriptQuickJSFixture.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

void mwx_fixture_dynamic_layer_creation_cases(MWXSceneScriptQuickJSFixture *fixture) {
    const char *dynamic_layer_source =
        "let shadow;"
        "export function init(value){"
        "shadow=thisScene.createLayer({text:'shadow',color:'0 0 0',alpha:1,"
        "pointsize:thisLayer.pointsize,font:thisLayer.font});"
        "shadow.origin=thisLayer.origin;shadow.scale=thisLayer.scale;"
        "thisScene.sortLayer(shadow,thisScene.getLayerIndex(thisLayer));"
        "shared.dynamicLayer=shadow;return value;}"
        "export function update(value){"
        "shadow.text='tick';shadow.angles=new Vec3(1,2,3);"
        "const listed=thisScene.enumerateLayers();"
        "if(listed.length!==3||listed[0].id!==17||"
        "listed[1].id!==shadow.id||listed[2].id!==42)"
        "throw new Error('dynamic render order');"
        "return thisScene.getLayerIndex(shadow)*100+thisScene.getLayerCount();}";
    fixture->dynamic_layer = mwx_scene_quickjs_owner_create(
        fixture->domain, dynamic_layer_source, strlen(dynamic_layer_source),
        40, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->dynamic_layer != NULL, "dynamic layer owner compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_configure_owner_layer(fixture->dynamic_layer, 42, "dynamic layer owner identity");
    fixture->failures += mwx_fixture_update(
        fixture->dynamic_layer, 40, 1, MWX_SCENE_QUICKJS_OK, 103,
        "dynamic layer create update"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_layer_mutation_count(fixture->dynamic_layer) == 1,
        "dynamic layer mutation coalesced", ""
    );
    fixture->failures += mwx_fixture_layer_mutation(
        fixture->dynamic_layer, 0, MWX_SCENE_QUICKJS_LAYER_MUTATION_UPSERT,
        1, 0, 0, 1, "tick", "dynamic layer snapshot"
    );
    // The product host finalizes every owner after the surface barrier.  Keep
    // the direct C harness at that same boundary before the next owner may
    // perform topology work.
    mwx_scene_quickjs_owner_commit_layer_mutations(fixture->dynamic_layer);

    const char *dynamic_matrix_source =
        "export function update(value){"
        "const layer=thisScene.createLayer({text:'matrix'});"
        "layer.getTransformMatrix();return value;}";
    fixture->dynamic_matrix = mwx_scene_quickjs_owner_create(
        fixture->domain, dynamic_matrix_source, strlen(dynamic_matrix_source),
        69, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->dynamic_matrix, 42, "dynamic matrix owner identity"
    );
    fixture->failures += mwx_fixture_update(
        fixture->dynamic_matrix, 69, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "uncommitted dynamic layer has no guessed world matrix"
    );
    fixture->failures += mwx_fixture_update(
        fixture->dynamic_layer, 40, 1, MWX_SCENE_QUICKJS_OK, 103,
        "dynamic layer handle persists"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_layer_mutation_count(fixture->dynamic_layer) == 0,
        "unchanged dynamic layer setters are deduplicated", ""
    );
    mwx_scene_quickjs_owner_commit_layer_mutations(fixture->dynamic_layer);

    const char *dynamic_image_configuration_source =
        "let image;export function init(value){image=thisScene.createLayer({"
        "image:'models/trail.json',origin:new Vec3(3,4,5),"
        "scale:new Vec3(6,7,8),color:new Vec3(0.1,0.2,0.3),"
        "alpha:0.4,visible:false});return value;}"
        "export function update(value){image.color=new Vec3(0.7,0.8,0.9);"
        "image.alpha=0.6;image.visible=true;return value;}";
    fixture->dynamic_image_configuration =
        mwx_scene_quickjs_owner_create(
            fixture->domain, dynamic_image_configuration_source,
            strlen(dynamic_image_configuration_source),
            61, fixture->diagnostic, sizeof(fixture->diagnostic)
        );
    fixture->failures += mwx_fixture_check(
        fixture->dynamic_image_configuration != NULL,
        "dynamic image configuration compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->dynamic_image_configuration, 17,
        "dynamic image configuration owner identity"
    );
    fixture->failures += mwx_fixture_update(
        fixture->dynamic_image_configuration, 61, 1, MWX_SCENE_QUICKJS_OK, 1,
        "dynamic image configuration update"
    );
    MWXSceneQuickJSLayerMutation dynamic_image_configuration_mutation = {0};
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_layer_mutation_at(
            fixture->dynamic_image_configuration, 0,
            &dynamic_image_configuration_mutation,
            fixture->diagnostic, sizeof(fixture->diagnostic)
        ) == MWX_SCENE_QUICKJS_OK &&
            strcmp(
                dynamic_image_configuration_mutation.asset_path,
                "models/trail.json"
            ) == 0 &&
            dynamic_image_configuration_mutation.origin[0] == 3 &&
            dynamic_image_configuration_mutation.origin[1] == 4 &&
            dynamic_image_configuration_mutation.origin[2] == 5 &&
            dynamic_image_configuration_mutation.scale[0] == 6 &&
            dynamic_image_configuration_mutation.scale[1] == 7 &&
            dynamic_image_configuration_mutation.scale[2] == 8 &&
            dynamic_image_configuration_mutation.color[0] == 0.7 &&
            dynamic_image_configuration_mutation.color[1] == 0.8 &&
            dynamic_image_configuration_mutation.color[2] == 0.9 &&
            dynamic_image_configuration_mutation.alpha == 0.6 &&
            dynamic_image_configuration_mutation.visible == 1,
        "dynamic image configuration fields published", fixture->diagnostic
    );
    mwx_scene_quickjs_owner_commit_layer_mutations(fixture->dynamic_image_configuration);

    const char *destroyed_enumerated_source =
        "export function update(value){"
        "const created=thisScene.createLayer({text:'temporary'});"
        "const listed=thisScene.enumerateLayers();const saved=listed[listed.length-1];"
        "if(saved.id!==created.id)throw new Error('dynamic enumeration tail');"
        "thisScene.destroyLayer(created);"
        "let stale=false;try{saved.id;}catch(error){stale=true;}"
        "if(!stale)throw new Error('destroyed handle survived');"
        "stale=false;try{saved.scale=new Vec3(NaN);}catch(error){stale=true;}"
        "if(!stale)throw new Error('stale NaN write survived');return value;}";
    fixture->destroyed_enumerated = mwx_scene_quickjs_owner_create(
        fixture->domain, destroyed_enumerated_source, strlen(destroyed_enumerated_source),
        53, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->destroyed_enumerated != NULL, "destroyed enumeration compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->destroyed_enumerated, 17, "destroyed enumeration owner identity"
    );
    fixture->failures += mwx_fixture_update(
        fixture->destroyed_enumerated, 53, 1, MWX_SCENE_QUICKJS_OK, 1,
        "destroyed enumerated handle becomes stale"
    );
    mwx_scene_quickjs_owner_commit_layer_mutations(fixture->destroyed_enumerated);

    fixture->dynamic_intruder = mwx_scene_quickjs_owner_create(
        fixture->domain,
        "export function update(value){const layer=thisScene.enumerateLayers()[1];"
        "let rejected=false;try{layer.text='intrusion';}catch(error){rejected=true;}"
        "if(!rejected)throw new Error('foreign dynamic write');"
        "rejected=false;try{layer.scale=new Vec3(NaN);}catch(error){rejected=true;}"
        "if(!rejected)throw new Error('foreign NaN write survived');"
        "return layer.text==='tick'?1:0;}",
        strlen(
            "export function update(value){const layer=thisScene.enumerateLayers()[1];"
            "let rejected=false;try{layer.text='intrusion';}catch(error){rejected=true;}"
            "if(!rejected)throw new Error('foreign dynamic write');"
        "rejected=false;try{layer.scale=new Vec3(NaN);}catch(error){rejected=true;}"
        "if(!rejected)throw new Error('foreign NaN write survived');"
            "return layer.text==='tick'?1:0;}"
        ),
        41, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->dynamic_intruder != NULL, "dynamic intruder compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_configure_owner_layer(fixture->dynamic_intruder, 17, "dynamic intruder identity");
    fixture->failures += mwx_fixture_update(
        fixture->dynamic_intruder, 41, 1, MWX_SCENE_QUICKJS_OK, 1,
        "cross-owner dynamic layer is readable but not writable"
    );

}

void mwx_fixture_dynamic_layer_transaction_cases(MWXSceneScriptQuickJSFixture *fixture) {
    const char *dynamic_budget_source =
        "export function update(value){let created=0;for(let i=0;i<65;i+=1)"
        "if(thisScene.createLayer({text:'x'}))created+=1;return created;}";
    fixture->dynamic_budget = mwx_scene_quickjs_owner_create(
        fixture->domain, dynamic_budget_source, strlen(dynamic_budget_source),
        42, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->dynamic_budget != NULL, "dynamic budget compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_configure_owner_layer(fixture->dynamic_budget, 17, "dynamic budget identity");
    fixture->failures += mwx_fixture_update(
        fixture->dynamic_budget, 42, 1, MWX_SCENE_QUICKJS_OK, 65,
        "dynamic layer creation crosses former owner cap"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_layer_mutation_count(fixture->dynamic_budget) == 65,
        "every admitted dynamic layer has a mutation", fixture->diagnostic
    );
    // Discarding the bounded batch also exercises the provisional-create
    // tombstones and keeps later fixtures independent of these 65 records.
    mwx_scene_quickjs_owner_discard_layer_mutations(fixture->dynamic_budget);

    // One owner may consume the existing scene-wide capacity. A second owner
    // cannot bypass it, and every admitted value still participates in rollback.
    MWXSceneQuickJSDomain *capacity_domain = mwx_scene_quickjs_domain_create(
        2 * 1024 * 1024, 512 * 1024, 100000, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(capacity_domain != NULL, "capacity domain", fixture->diagnostic);
    fixture->failures += mwx_fixture_configure_layers(capacity_domain);
    const char *capacity_source =
        "let layers=[];export function update(v){"
        "if(v===1){for(let i=0;i<257;i++){"
        "let x=thisScene.createLayer({text:'x',name:'wide'+i});"
        "if(x)layers.push(x);}return layers.length;}"
        "if(v===2){for(let x of layers)x.scale=new Vec3(2);return layers.length;}"
        "if(v===3){for(let x of layers)if(x.scale.x!==1)throw new Error('leak');"
        "return layers.length;}"
        "if(v===4){for(let i=0;i<128;i++)thisScene.destroyLayer(layers[i]);return 128;}"
        "return v;}";
    MWXSceneQuickJSOwner *capacity_owner = mwx_scene_quickjs_owner_create(
        capacity_domain, capacity_source, strlen(capacity_source),
        800, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(capacity_owner != NULL, "capacity owner", fixture->diagnostic);
    fixture->failures += mwx_fixture_configure_owner_layer(capacity_owner, 17, "capacity target");
    fixture->failures += mwx_fixture_update(capacity_owner, 800, 1, MWX_SCENE_QUICKJS_OK, 256,
        "single owner can fill scene capacity and excess returns null");
    fixture->failures += mwx_fixture_check(mwx_scene_quickjs_owner_layer_mutation_count(capacity_owner) == 256,
        "all creations publish", fixture->diagnostic);
    mwx_scene_quickjs_owner_commit_layer_mutations(capacity_owner);
    const char *competitor_source =
        "export function update(v){let n=0;for(let i=0;i<v;i++)"
        "if(thisScene.createLayer({text:'other'}))n++;return n;}";
    MWXSceneQuickJSOwner *competitor = mwx_scene_quickjs_owner_create(
        capacity_domain, competitor_source, strlen(competitor_source),
        801, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(competitor != NULL, "competing owner", fixture->diagnostic);
    fixture->failures += mwx_fixture_configure_owner_layer(competitor, 42, "competing target");
    fixture->failures += mwx_fixture_update(competitor, 801, 1, MWX_SCENE_QUICKJS_OK, 0,
        "scene capacity applies across owners");
    fixture->failures += mwx_fixture_update(capacity_owner, 800, 2, MWX_SCENE_QUICKJS_OK, 256,
        "full-capacity values stage");
    fixture->failures += mwx_fixture_check(mwx_scene_quickjs_owner_layer_mutation_count(capacity_owner) == 256,
        "full-capacity values publish", fixture->diagnostic);
    mwx_scene_quickjs_owner_discard_layer_mutations(capacity_owner);
    fixture->failures += mwx_fixture_update(capacity_owner, 800, 3, MWX_SCENE_QUICKJS_OK, 256,
        "discard restores every value above old owner cap");
    fixture->failures += mwx_fixture_update(capacity_owner, 800, 4, MWX_SCENE_QUICKJS_OK, 128,
        "destroy releases scene capacity");
    mwx_scene_quickjs_owner_commit_layer_mutations(capacity_owner);
    fixture->failures += mwx_fixture_update(competitor, 801, 129, MWX_SCENE_QUICKJS_OK, 128,
        "released capacity reusable but still bounded");
    mwx_scene_quickjs_owner_discard_layer_mutations(competitor);
    fixture->failures += mwx_fixture_update(competitor, 801, 129, MWX_SCENE_QUICKJS_OK, 128,
        "discarded creations release capacity for retry");
    mwx_scene_quickjs_owner_destroy(competitor);
    mwx_scene_quickjs_owner_destroy(capacity_owner);
    mwx_scene_quickjs_domain_destroy(capacity_domain);

    const char *dynamic_rollback_source =
        "let layer;"
        "export function init(value){layer=thisScene.createLayer({"
        "name:'rollback',text:'stable'});return value;}"
        "export function update(value){if(value===2){layer.text='leak';"
        "thisScene.sortLayer(layer,0);throw new Error('reject frame');}"
        "return value;}";
    fixture->dynamic_rollback = mwx_scene_quickjs_owner_create(
        fixture->domain, dynamic_rollback_source, strlen(dynamic_rollback_source),
        67, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->dynamic_rollback != NULL, "dynamic rollback owner compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->dynamic_rollback, 17, "dynamic rollback owner identity"
    );
    fixture->failures += mwx_fixture_update(
        fixture->dynamic_rollback, 67, 1, MWX_SCENE_QUICKJS_OK, 1,
        "dynamic rollback baseline created"
    );
    mwx_scene_quickjs_owner_commit_layer_mutations(fixture->dynamic_rollback);

    const char *dynamic_rollback_observer_source =
        "export function update(value){let marker=-1;"
        "for(const layer of thisScene.enumerateLayers())"
        "if(layer.name==='rollback')marker=layer.text==='stable'"
        "?thisScene.getLayerIndex(layer):-2;"
        "return thisScene.getLayerCount()*10+marker;}";
    fixture->dynamic_rollback_observer =
        mwx_scene_quickjs_owner_create(
            fixture->domain, dynamic_rollback_observer_source,
            strlen(dynamic_rollback_observer_source),
            68, fixture->diagnostic, sizeof(fixture->diagnostic)
        );
    fixture->failures += mwx_fixture_check(
        fixture->dynamic_rollback_observer != NULL,
        "dynamic rollback observer compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->dynamic_rollback_observer, 68, 0, MWX_SCENE_QUICKJS_OK, 54,
        "dynamic rollback baseline is observable"
    );
    fixture->failures += mwx_fixture_update(
        fixture->dynamic_rollback, 67, 2, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "dynamic value and order failure rejects owner transaction"
    );
    fixture->failures += mwx_fixture_update(
        fixture->dynamic_rollback_observer, 68, 0, MWX_SCENE_QUICKJS_OK, 54,
        "dynamic value and order failure restores previous current"
    );

    const char *dynamic_create_failure_source =
        "export function update(value){"
        "thisScene.createLayer({name:'ghost',text:'ghost'});"
        "throw new Error('reject create');}";
    fixture->dynamic_create_failure =
        mwx_scene_quickjs_owner_create(
            fixture->domain, dynamic_create_failure_source,
            strlen(dynamic_create_failure_source),
            69, fixture->diagnostic, sizeof(fixture->diagnostic)
        );
    fixture->failures += mwx_fixture_check(
        fixture->dynamic_create_failure != NULL,
        "dynamic create failure owner compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->dynamic_create_failure, 69, 0,
        MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "failed callback tombstones provisional dynamic layer"
    );
    fixture->failures += mwx_fixture_update(
        fixture->dynamic_rollback_observer, 68, 0, MWX_SCENE_QUICKJS_OK, 54,
        "failed create leaves no observable ghost layer"
    );

    const char *dynamic_explicit_discard_source =
        "export function update(value){"
        "thisScene.createLayer({name:'discard',text:'discard'});"
        "return thisScene.getLayerCount();}";
    fixture->dynamic_explicit_discard =
        mwx_scene_quickjs_owner_create(
            fixture->domain, dynamic_explicit_discard_source,
            strlen(dynamic_explicit_discard_source),
            70, fixture->diagnostic, sizeof(fixture->diagnostic)
        );
    fixture->failures += mwx_fixture_check(
        fixture->dynamic_explicit_discard != NULL,
        "dynamic explicit discard owner compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->dynamic_explicit_discard, 70, 0, MWX_SCENE_QUICKJS_OK, 6,
        "provisional create is visible to its callback"
    );
    mwx_scene_quickjs_owner_discard_layer_mutations(
        fixture->dynamic_explicit_discard
    );
    fixture->failures += mwx_fixture_update(
        fixture->dynamic_rollback_observer, 68, 0, MWX_SCENE_QUICKJS_OK, 54,
        "explicit discard restores dynamic topology"
    );

    const char *dynamic_invalidate_source =
        "export function update(value){"
        "thisScene.createLayer({name:'invalidate',text:'invalidate'});"
        "return thisScene.getLayerCount();}";
    fixture->dynamic_invalidate = mwx_scene_quickjs_owner_create(
        fixture->domain, dynamic_invalidate_source, strlen(dynamic_invalidate_source),
        71, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->dynamic_invalidate != NULL,
        "dynamic invalidate owner compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->dynamic_invalidate, 71, 0, MWX_SCENE_QUICKJS_OK, 6,
        "provisional create precedes owner invalidation"
    );
    mwx_scene_quickjs_owner_invalidate(fixture->dynamic_invalidate);
    fixture->failures += mwx_fixture_update(
        fixture->dynamic_rollback_observer, 68, 0, MWX_SCENE_QUICKJS_OK, 54,
        "owner invalidation discards provisional dynamic topology"
    );

    // Dynamic topology is a frame-scoped candidate, not a single-owner lock.
    // Both callbacks may observe and extend the same provisional order before
    // the host reaches its surface barrier.
    const char *multi_owner_a_source =
        "let layer;export function update(value){"
        "layer=thisScene.createLayer({name:'multi-a',text:'a'});"
        "thisScene.sortLayer(layer,0);"
        "if(thisScene.getLayerIndex(layer)!==0)throw new Error('multi-a order');"
        "return thisScene.getLayerCount();}";
    fixture->multi_owner_a = mwx_scene_quickjs_owner_create(
        fixture->domain, multi_owner_a_source, strlen(multi_owner_a_source),
        73, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->multi_owner_a != NULL, "multi-owner A compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->multi_owner_a, 17, "multi-owner A identity"
    );
    fixture->failures += mwx_fixture_update(
        fixture->multi_owner_a, 73, 1, MWX_SCENE_QUICKJS_OK, 6,
        "multi-owner A provisional topology"
    );

    const char *multi_owner_b_source =
        "let layer;export function update(value){"
        "const listed=thisScene.enumerateLayers();"
        "if(listed[0].name!=='multi-a')throw new Error('multi-owner A missing');"
        "layer=thisScene.createLayer({name:'multi-b',text:'b'});"
        "thisScene.sortLayer(layer,1);"
        "if(thisScene.getLayerIndex(layer)!==1)throw new Error('multi-b order');"
        "return thisScene.getLayerCount();}";
    fixture->multi_owner_b = mwx_scene_quickjs_owner_create(
        fixture->domain, multi_owner_b_source, strlen(multi_owner_b_source),
        74, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->multi_owner_b != NULL, "multi-owner B compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->multi_owner_b, 42, "multi-owner B identity"
    );
    fixture->failures += mwx_fixture_update(
        fixture->multi_owner_b, 74, 1, MWX_SCENE_QUICKJS_OK, 7,
        "multi-owner B appends before barrier"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_layer_mutation_count(fixture->multi_owner_a) == 1 &&
            mwx_scene_quickjs_owner_layer_mutation_count(fixture->multi_owner_b) == 1,
        "multi-owner topology mutations remain owner-scoped", fixture->diagnostic
    );
    mwx_scene_quickjs_owner_commit_layer_mutations(fixture->multi_owner_a);
    mwx_scene_quickjs_owner_commit_layer_mutations(fixture->multi_owner_b);

    const char *multi_owner_bad_source =
        "export function update(value){"
        "thisScene.createLayer({name:'multi-bad',text:'bad'});"
        "thisScene.sortLayer(thisScene.getLayer('multi-bad'),0);"
        "return thisScene.getLayerCount();}";
    fixture->multi_owner_bad = mwx_scene_quickjs_owner_create(
        fixture->domain, multi_owner_bad_source, strlen(multi_owner_bad_source),
        75, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->multi_owner_bad != NULL, "multi-owner rollback bad compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->multi_owner_bad, 17, "multi-owner rollback bad identity"
    );
    fixture->failures += mwx_fixture_update(
        fixture->multi_owner_bad, 75, 1, MWX_SCENE_QUICKJS_OK, 8,
        "multi-owner rejected candidate succeeds before admission"
    );

    const char *multi_owner_good_source =
        "export function update(value){"
        "let sawBad=false;for(const layer of thisScene.enumerateLayers())"
        "if(layer.name==='multi-bad')sawBad=true;"
        "if(!sawBad)throw new Error('multi-bad was not provisional');"
        "thisScene.createLayer({name:'multi-good',text:'good'});"
        "return thisScene.getLayerCount();}";
    fixture->multi_owner_good = mwx_scene_quickjs_owner_create(
        fixture->domain, multi_owner_good_source, strlen(multi_owner_good_source),
        76, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->multi_owner_good != NULL, "multi-owner rollback good compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->multi_owner_good, 42, "multi-owner rollback good identity"
    );
    fixture->failures += mwx_fixture_update(
        fixture->multi_owner_good, 76, 1, MWX_SCENE_QUICKJS_OK, 9,
        "multi-owner good peer observes rejected candidate"
    );
    mwx_scene_quickjs_owner_discard_layer_mutations(fixture->multi_owner_bad);
    mwx_scene_quickjs_owner_commit_layer_mutations(fixture->multi_owner_good);

    const char *multi_owner_observer_source =
        "export function update(value){let bad=false,good=false;"
        "for(const layer of thisScene.enumerateLayers()){"
        "if(layer.name==='multi-bad')bad=true;"
        "if(layer.name==='multi-good')good=true;}"
        "return (bad?100:0)+(good?10:0)+thisScene.getLayerCount();}";
    fixture->multi_owner_observer = mwx_scene_quickjs_owner_create(
        fixture->domain, multi_owner_observer_source,
        strlen(multi_owner_observer_source), 77,
        fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->multi_owner_observer != NULL, "multi-owner rollback observer compile",
        fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->multi_owner_observer, 77, 0, MWX_SCENE_QUICKJS_OK, 18,
        "multi-owner discard replays admitted peer only"
    );
    mwx_scene_quickjs_owner_commit_layer_mutations(fixture->multi_owner_observer);

}

void mwx_fixture_layer_order_cases(MWXSceneScriptQuickJSFixture *fixture) {
    // Authored sorts: run after every other order-sensitive fixture because
    // the sort permanently shifts the shared catalog order. The order-only
    // mutation carries the new index to Swift. Layer 42's index at this point
    // is whatever earlier fixtures left; the assertions pin the shape, not an
    // absolute index.
    fixture->static_sort = mwx_scene_quickjs_owner_create(
        fixture->domain,
        "export function update(value){thisScene.sortLayer(thisLayer,0);return value;}",
        strlen("export function update(value){thisScene.sortLayer(thisLayer,0);return value;}"),
        44, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->static_sort != NULL, "static sort owner compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_configure_owner_layer(fixture->static_sort, 42, "static sort owner identity");
    fixture->failures += mwx_fixture_update(
        fixture->static_sort, 44, 1, MWX_SCENE_QUICKJS_OK, 1,
        "authored layer sort accepted"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_layer_mutation_count(fixture->static_sort) == 1,
        "authored layer sort mutation staged", ""
    );
    {
        MWXSceneQuickJSLayerMutation sort_mutation = {0};
        fixture->failures += mwx_fixture_check(
            mwx_scene_quickjs_owner_layer_mutation_at(
                fixture->static_sort, 0, &sort_mutation, fixture->diagnostic, sizeof(fixture->diagnostic)
            ) == MWX_SCENE_QUICKJS_OK
                && sort_mutation.kind == MWX_SCENE_QUICKJS_LAYER_MUTATION_UPSERT
                && sort_mutation.dynamic == 0
                && sort_mutation.fields == 0
                && sort_mutation.layer_id == 42,
            "authored layer sort order-only mutation", ""
        );
    }
    // Committing the sort owner runs the topology rebuild: the journaled
    // authored SORT op replays through the relaxed authored branch and the
    // new order is what later owners read.
    mwx_scene_quickjs_owner_commit_layer_mutations(fixture->static_sort);
    const char *sort_order_readback_source =
        "export function update(value){"
        "return thisScene.getLayer(0).id===42?1:0;}";
    fixture->sort_order_readback = mwx_scene_quickjs_owner_create(
        fixture->domain, sort_order_readback_source, strlen(sort_order_readback_source),
        49, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->sort_order_readback != NULL, "sort order readback compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->sort_order_readback, 17, "sort order readback owner identity"
    );
    fixture->failures += mwx_fixture_update(
        fixture->sort_order_readback, 49, 1, MWX_SCENE_QUICKJS_OK, 1,
        "committed authored sort survives the topology rebuild"
    );

    // Mixed-frame cross-check: one callback creates a dynamic text layer at
    // index 0 and sorts authored layer 42 to index 1. The committed rebuild
    // must reproduce the C final order [created, 42, ...] - the same
    // final-position pattern the Swift runtime fixtures assert.
    fixture->mixed_frame = mwx_scene_quickjs_owner_create(
        fixture->domain,
        "export function update(value){"
        "const created=thisScene.createLayer({text:'mwx-mixed'});"
        "if(created==null)return -1;"
        "thisScene.sortLayer(thisLayer,1);"
        "const createdIndex=thisScene.getLayerIndex(created);"
        "const sortedIndex=thisScene.getLayerIndex(thisLayer);"
        "const ok=(createdIndex>1&&sortedIndex===1)?1:0;"
        "thisScene.destroyLayer(created);"
        "return ok;}",
        strlen("export function update(value){"
        "const created=thisScene.createLayer({text:'mwx-mixed'});"
        "if(created==null)return -1;"
        "thisScene.sortLayer(thisLayer,1);"
        "const createdIndex=thisScene.getLayerIndex(created);"
        "const sortedIndex=thisScene.getLayerIndex(thisLayer);"
        "const ok=(createdIndex>1&&sortedIndex===1)?1:0;"
        "thisScene.destroyLayer(created);"
        "return ok;}"),
        52, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->mixed_frame != NULL, "mixed frame compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->mixed_frame, 42, "mixed frame owner identity"
    );
    fixture->failures += mwx_fixture_update(
        fixture->mixed_frame, 52, 1, MWX_SCENE_QUICKJS_OK, 1,
        "mixed frame reproduces the C final order [created, 42, ...]"
    );

}
