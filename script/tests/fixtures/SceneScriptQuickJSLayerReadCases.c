#include "SceneScriptQuickJSFixture.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

void mwx_fixture_layer_catalog_admission_cases(MWXSceneScriptQuickJSFixture *fixture) {
    MWXSceneQuickJSDomain *invalid_parent_domain = mwx_scene_quickjs_domain_create(
        2 * 1024 * 1024, 512 * 1024, 100000, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        invalid_parent_domain != NULL, "invalid parent domain", fixture->diagnostic
    );
    if (invalid_parent_domain != NULL) {
        const double origin[3] = {0, 0, 0};
        const double size[2] = {0, 0};
        MWXSceneQuickJSResult invalid_parent_result =
            mwx_scene_quickjs_domain_configure_layer_catalog(
                invalid_parent_domain, 1, 0, fixture->diagnostic, sizeof(fixture->diagnostic)
            );
        if (invalid_parent_result == MWX_SCENE_QUICKJS_OK) {
            invalid_parent_result = mwx_scene_quickjs_domain_set_layer_descriptor(
                invalid_parent_domain, 0, 7, 1, 999,
                "orphan", strlen("orphan"), origin,
                size,
                fixture->diagnostic, sizeof(fixture->diagnostic)
            );
        }
        fixture->failures += mwx_fixture_check(
            invalid_parent_result == MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
            "invalid authored parent rejected",
            fixture->diagnostic
        );
        mwx_scene_quickjs_domain_destroy(invalid_parent_domain);
    }
    MWXSceneQuickJSDomain *invalid_size_domain =
        mwx_scene_quickjs_domain_create(
            2 * 1024 * 1024, 512 * 1024, 100000,
            fixture->diagnostic, sizeof(fixture->diagnostic)
        );
    fixture->failures += mwx_fixture_check(
        invalid_size_domain != NULL, "invalid size domain", fixture->diagnostic
    );
    if (invalid_size_domain != NULL) {
        const double origin[3] = {0, 0, 0};
        const double invalid_size[2] = {NAN, 1};
        MWXSceneQuickJSResult invalid_size_result =
            mwx_scene_quickjs_domain_configure_layer_catalog(
                invalid_size_domain, 1, 0, fixture->diagnostic, sizeof(fixture->diagnostic)
            );
        if (invalid_size_result == MWX_SCENE_QUICKJS_OK) {
            invalid_size_result = mwx_scene_quickjs_domain_set_layer_descriptor(
                invalid_size_domain, 0, 8, 0, 0,
                "invalid-size", strlen("invalid-size"), origin,
                invalid_size, fixture->diagnostic, sizeof(fixture->diagnostic)
            );
        }
        fixture->failures += mwx_fixture_check(
            invalid_size_result == MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
            "non-finite authored size rejected", fixture->diagnostic
        );
        mwx_scene_quickjs_domain_destroy(invalid_size_domain);
    }
    // Configuration may arrive out of order. Failed/repeated slots must not
    // publish a partial catalog or bypass final parent/identity checks.
    for (int scenario = 0; scenario < 3; ++scenario) {
        MWXSceneQuickJSDomain *reordered = mwx_scene_quickjs_domain_create(
            2 * 1024 * 1024, 512 * 1024, 100000,
            fixture->diagnostic, sizeof(fixture->diagnostic)
        );
        fixture->failures += mwx_fixture_check(
            reordered != NULL, "reordered catalog domain", fixture->diagnostic
        );
        if (reordered == NULL) continue;
        const double origin[3] = {0, 0, 0};
        const double size[2] = {1, 1};
        const double bad_size[2] = {NAN, 1};
        MWXSceneQuickJSResult result = mwx_scene_quickjs_domain_configure_layer_catalog(
            reordered, 3, 0, fixture->diagnostic, sizeof(fixture->diagnostic)
        );
        if (result == MWX_SCENE_QUICKJS_OK) {
            result = mwx_scene_quickjs_domain_set_layer_descriptor(
                reordered, 2, 30, 1, scenario == 2 ? 999 : 20,
                "child", 5, origin, size, fixture->diagnostic, sizeof(fixture->diagnostic)
            );
        }
        fixture->failures += mwx_fixture_check(
            result == MWX_SCENE_QUICKJS_OK,
            "later parent may be configured after child", fixture->diagnostic
        );
        result = mwx_scene_quickjs_domain_set_layer_descriptor(
            reordered, 2, 30, 0, 0, "repeated", 8,
            origin, size, fixture->diagnostic, sizeof(fixture->diagnostic)
        );
        fixture->failures += mwx_fixture_check(
            result == MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
            "repeated slot is rejected before complete catalog", fixture->diagnostic
        );
        result = mwx_scene_quickjs_domain_set_layer_descriptor(
            reordered, 0, 10, 0, 0, "root", 4,
            origin, size, fixture->diagnostic, sizeof(fixture->diagnostic)
        );
        fixture->failures += mwx_fixture_check(
            result == MWX_SCENE_QUICKJS_OK, "reordered root accepted", fixture->diagnostic
        );
        result = mwx_scene_quickjs_domain_set_layer_descriptor(
            reordered, 1, 20, 1, 10, "parent", 6,
            origin, bad_size, fixture->diagnostic, sizeof(fixture->diagnostic)
        );
        fixture->failures += mwx_fixture_check(
            result == MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
            "failed slot remains available for correction", fixture->diagnostic
        );
        result = mwx_scene_quickjs_domain_set_layer_descriptor(
            reordered, 1, scenario == 1 ? 10 : 20, scenario == 1 ? 0 : 1, 10,
            "parent", 6, origin, size, fixture->diagnostic, sizeof(fixture->diagnostic)
        );
        fixture->failures += mwx_fixture_check(
            result == (scenario == 0 ? MWX_SCENE_QUICKJS_OK : MWX_SCENE_QUICKJS_INVALID_ARGUMENT),
            scenario == 0 ? "reordered corrected catalog is accepted"
                : "complete catalog still rejects duplicate identity or missing parent",
            fixture->diagnostic
        );
        mwx_scene_quickjs_domain_destroy(reordered);
    }
    MWXSceneQuickJSDomain *empty_catalog = mwx_scene_quickjs_domain_create(
        2 * 1024 * 1024, 512 * 1024, 100000,
        fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(empty_catalog != NULL, "empty catalog domain", fixture->diagnostic);
    if (empty_catalog != NULL) {
        fixture->failures += mwx_fixture_check(
            mwx_scene_quickjs_domain_configure_layer_catalog(
                empty_catalog, 0, 0, fixture->diagnostic, sizeof(fixture->diagnostic)
            ) == MWX_SCENE_QUICKJS_OK,
            "empty authored catalog remains valid", fixture->diagnostic
        );
        mwx_scene_quickjs_domain_destroy(empty_catalog);
    }
    MWXSceneQuickJSDomain *authored_budget_domain = mwx_scene_quickjs_domain_create(
        2 * 1024 * 1024, 512 * 1024, 100000,
        fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        authored_budget_domain != NULL, "authored mutation budget domain", fixture->diagnostic
    );
    if (authored_budget_domain != NULL) {
        MWXSceneQuickJSResult budget_catalog_result =
            mwx_scene_quickjs_domain_configure_layer_catalog(
                authored_budget_domain, 257, 0, fixture->diagnostic, sizeof(fixture->diagnostic)
            );
        for (uint32_t index = 0;
             index < 257 && budget_catalog_result == MWX_SCENE_QUICKJS_OK;
             ++index) {
            char name[32] = {0};
            snprintf(name, sizeof(name), "authored-%u", index);
            const double origin[3] = {(double)index, 0, 0};
            const double size[2] = {0, 0};
            budget_catalog_result = mwx_scene_quickjs_domain_set_layer_descriptor(
                authored_budget_domain, index, 1000 + index, 0, 0,
                name, strlen(name), origin, size,
                fixture->diagnostic, sizeof(fixture->diagnostic)
            );
        }
        fixture->failures += mwx_fixture_check(
            budget_catalog_result == MWX_SCENE_QUICKJS_OK,
            "authored mutation budget catalog", fixture->diagnostic
        );
        const char *authored_budget_source =
            "export function update(value){for(let i=0;i<257;i+=1)"
            "thisScene.getLayerByID(1000+i).visible=false;return value;}";
        MWXSceneQuickJSOwner *authored_budget = mwx_scene_quickjs_owner_create(
            authored_budget_domain, authored_budget_source,
            strlen(authored_budget_source), 61, fixture->diagnostic, sizeof(fixture->diagnostic)
        );
        fixture->failures += mwx_fixture_check(
            authored_budget != NULL, "authored mutation budget compile", fixture->diagnostic
        );
        if (authored_budget != NULL) {
            fixture->failures += mwx_fixture_configure_owner_layer(
                authored_budget, 1000, "authored mutation budget owner identity"
            );
            fixture->failures += mwx_fixture_update(
                authored_budget, 61, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
                "authored mutation budget rejects target 257"
            );
            fixture->failures += mwx_fixture_check(
                mwx_scene_quickjs_owner_layer_mutation_count(authored_budget) == 0,
                "authored mutation overflow rolls back 256 staged targets", fixture->diagnostic
            );
            mwx_scene_quickjs_owner_destroy(authored_budget);
        }
        mwx_scene_quickjs_domain_destroy(authored_budget_domain);
    }
}

void mwx_fixture_layer_read_snapshot_cases(MWXSceneScriptQuickJSFixture *fixture) {
    const char *layer_source =
        "export function update(value) {"
        "const day=1; const layer=thisScene.getLayer(`C${day}`);"
        "const listed=thisScene.enumerateLayers();"
        "if(listed.length!==2||listed[0].id!==17||listed[1].id!==42||"
        "listed[0].getParent()!==undefined||layer.getParent().id!==17||"
        "thisScene.getLayerCount()!==2||thisScene.getLayer(1).id!==42||"
        "thisScene.getLayerByID(42).name!=='C1'||"
        "thisScene.getLayer('missing')!==null||thisScene.getLayer(9)!==null||"
        "thisScene.getLayerByID(999)!==null)throw new Error('layer identity');"
        "return layer.origin.copy().add(new Vec3(1,1,1));}";
    fixture->layer_owner = mwx_scene_quickjs_owner_create(
        fixture->domain, layer_source, strlen(layer_source),
        13, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->layer_owner != NULL, "layer handle compile", fixture->diagnostic);
    const double layer_input[3] = {0, 0, 0};
    const double layer_output[3] = {5, 6, 7};
    fixture->failures += mwx_fixture_update_vec3(
        fixture->layer_owner, 13, layer_input, "", "{}", MWX_SCENE_QUICKJS_OK,
        layer_output, "layer current origin"
    );

    const char *persistent_layer_source =
        "let saved; export function init(){"
        "saved=thisScene.enumerateLayers()[1].getParent();}"
        "export function update(){return saved.origin;}";
    fixture->persistent_layer = mwx_scene_quickjs_owner_create(
        fixture->domain, persistent_layer_source, strlen(persistent_layer_source),
        14, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->persistent_layer != NULL, "persistent layer compile", fixture->diagnostic
    );
    const double current_layer[3] = {1, 2, 3};
    fixture->failures += mwx_fixture_update_vec3(
        fixture->persistent_layer, 14, layer_input, "", "{}", MWX_SCENE_QUICKJS_OK,
        current_layer, "layer handle survives init to update"
    );
    fixture->failures += mwx_fixture_update_vec3(
        fixture->persistent_layer, 14, layer_input, "", "{}", MWX_SCENE_QUICKJS_OK,
        current_layer, "layer handle survives later callbacks"
    );

    const char *matrix_source =
        "let parent,oldCopy;"
        "export function init(){"
        "parent=thisLayer.getParent();oldCopy=thisLayer.getTransformMatrix();}"
        "export function update(value){"
        "const current=thisLayer.getTransformMatrix();"
        "const parentMatrix=parent.getTransformMatrix();"
        "if(!(current instanceof Mat4)||!(parentMatrix instanceof Mat4))"
        "throw new Error('matrix type');"
        "if(value===1){"
        "if(current.m[12]!==33||current.m[13]!==44||"
        "parentMatrix.m[12]!==11||parentMatrix.m[13]!==22)"
        "throw new Error('initial matrix');"
        "const isolated=thisLayer.getTransformMatrix();isolated.m[12]=999;"
        "thisLayer.origin=new Vec3(9,9,9);"
        "if(thisLayer.getTransformMatrix().m[12]!==33)"
        "throw new Error('same callback matrix changed');"
        "}else if(value===2){"
        "if(current.m[12]!==33||parentMatrix.m[12]!==11||oldCopy.m[12]!==33)"
        "throw new Error('aborted matrix leaked');"
        "}else if(value===3){"
        "if(current.m[12]!==55||current.m[13]!==66||"
        "parentMatrix.m[12]!==77||parentMatrix.m[13]!==88||"
        "oldCopy.m[12]!==33||oldCopy.m[13]!==44)"
        "throw new Error('committed matrix visibility');"
        "}return value;}";
    fixture->matrix_owner = mwx_scene_quickjs_owner_create(
        fixture->domain, matrix_source, strlen(matrix_source),
        67, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->matrix_owner != NULL, "world matrix compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->matrix_owner, 42, "world matrix owner identity"
    );
    fixture->failures += mwx_fixture_update(
        fixture->matrix_owner, 67, 1, MWX_SCENE_QUICKJS_OK, 1,
        "world matrix initial immutable snapshot"
    );
    fixture->failures += mwx_fixture_reject_nonfinite_layer_world_snapshot(fixture->domain);
    fixture->failures += mwx_fixture_update(
        fixture->matrix_owner, 67, 2, MWX_SCENE_QUICKJS_OK, 2,
        "aborted world matrix snapshot remains invisible"
    );
    fixture->failures += mwx_fixture_commit_layer_world_snapshot(fixture->domain);
    fixture->failures += mwx_fixture_update(
        fixture->matrix_owner, 67, 3, MWX_SCENE_QUICKJS_OK, 3,
        "persistent handles see next committed world matrix"
    );

    const char *invalid_matrix_argument_source =
        "export function update(value){"
        "thisLayer.getTransformMatrix(1);return value;}";
    fixture->invalid_matrix_argument =
        mwx_scene_quickjs_owner_create(
            fixture->domain, invalid_matrix_argument_source,
            strlen(invalid_matrix_argument_source),
            68, fixture->diagnostic, sizeof(fixture->diagnostic)
        );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->invalid_matrix_argument, 42, "matrix argument owner identity"
    );
    fixture->failures += mwx_fixture_update(
        fixture->invalid_matrix_argument, 68, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "getTransformMatrix rejects arguments"
    );

    const char *value_only_layers_source =
        "export function update(value){"
        "const listed=thisScene.enumerateLayers();"
        "if(listed.length!==2||listed[1].getParent().id!==17)"
        "throw new Error('value-only enumeration');"
        "const writes=["
        "()=>{listed[0].origin=new Vec3(7,8,9);},"
        "()=>{listed[0].scale=new Vec3(2,3,4);},"
        "()=>{listed[0].angles=new Vec3(1,2,3);},"
        "()=>{listed[0].visible=false;},"
        "()=>{listed[0].solid=false;},"
        "()=>{listed[0].perspective=true;},"
        "()=>{listed[1].solid=false;},"
        "()=>{listed[0].text='peer';}];"
        "for(const write of writes){let rejected=false;"
        "try{write();}catch(error){rejected=true;}"
        "if(!rejected)throw new Error('writable peer');}"
        "if(listed[0].visible!==true||listed[0].text!=='')"
        "throw new Error('value-only peer residue');"
        "listed[1].visible=value;"
        "if(listed[1].visible!==true)throw new Error('readonly owner target');"
        "return value;}";
    fixture->value_only_create_result = MWX_SCENE_QUICKJS_OK;
    fixture->value_only_layers =
        mwx_scene_quickjs_owner_create_value_only_with_budget(
            fixture->domain, value_only_layers_source, strlen(value_only_layers_source),
            52, 100000, &fixture->value_only_create_result,
            fixture->diagnostic, sizeof(fixture->diagnostic)
        );
    fixture->failures += mwx_fixture_check(
        fixture->value_only_layers != NULL &&
            fixture->value_only_create_result == MWX_SCENE_QUICKJS_OK,
        "value-only layer enumeration compile",
        fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->value_only_layers, 42, "value-only layer identity"
    );
    fixture->failures += mwx_fixture_update_bool(
        fixture->value_only_layers, 52, 1, MWX_SCENE_QUICKJS_OK, 1,
        "value-only enumeration preserves exact target authority"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_layer_mutation_count(fixture->value_only_layers) == 0,
        "value-only enumeration rejected peers and kept target stable",
        fixture->diagnostic
    );

}

void mwx_fixture_forged_layer_cases(MWXSceneScriptQuickJSFixture *fixture) {
    const char *forged_layer_source =
        "export function update(value){"
        "if(thisScene.getLayerIndex({id:42})!==-1)throw new Error('forged index');"
        "thisScene.sortLayer({id:42},0);return value;}";
    fixture->forged_layer = mwx_scene_quickjs_owner_create(
        fixture->domain, forged_layer_source, strlen(forged_layer_source),
        43, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->forged_layer != NULL, "forged layer owner compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_configure_owner_layer(fixture->forged_layer, 42, "forged layer owner identity");
    fixture->failures += mwx_fixture_update(
        fixture->forged_layer, 43, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "forged layer object rejected"
    );

}
