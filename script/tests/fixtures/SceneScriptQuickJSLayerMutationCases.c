#include "SceneScriptQuickJSFixture.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

static MWXSceneQuickJSDomain *font_contract_domain(MWXSceneScriptQuickJSFixture *fixture) {
    MWXSceneQuickJSDomain *domain = mwx_scene_quickjs_domain_create(
        2 * 1024 * 1024, 512 * 1024, 100000, fixture->diagnostic, sizeof(fixture->diagnostic));
    fixture->failures += mwx_fixture_check(domain != NULL, "font path domain", fixture->diagnostic);
    if (domain == NULL) return NULL;
    fixture->failures += mwx_fixture_configure_layers(domain);
    mwx_scene_quickjs_domain_finalize_layer_snapshot(domain);
    const double scale[3] = {1, 1, 1}, angles[3] = {0, 0, 0}, color[3] = {1, 1, 1};
    MWXSceneQuickJSResult result = mwx_scene_quickjs_domain_begin_layer_snapshot(
        domain, 2, 0, fixture->diagnostic, sizeof(fixture->diagnostic));
    if (result == MWX_SCENE_QUICKJS_OK)
        result = mwx_scene_quickjs_domain_update_layer_runtime_fields(
            domain, 0, scale, angles, 0, 1, 1, 0, 1, "baseline", 8,
            "fonts/Baseline.ttf", strlen("fonts/Baseline.ttf"), 32, color,
            fixture->diagnostic, sizeof(fixture->diagnostic));
    if (result == MWX_SCENE_QUICKJS_OK)
        result = mwx_scene_quickjs_domain_reuse_layer_runtime_fields(
            domain, 1, fixture->diagnostic, sizeof(fixture->diagnostic));
    if (result == MWX_SCENE_QUICKJS_OK)
        result = mwx_scene_quickjs_domain_commit_layer_snapshot(
            domain, fixture->diagnostic, sizeof(fixture->diagnostic));
    fixture->failures += mwx_fixture_check(result == MWX_SCENE_QUICKJS_OK,
        "font path committed baseline", fixture->diagnostic);
    mwx_scene_quickjs_domain_finalize_layer_snapshot(domain);
    return domain;
}

static void font_path_contract_cases(MWXSceneScriptQuickJSFixture *fixture) {
    int positive[2] = {0, 0}, no_op[2] = {0, 0}, invalid = 0, rollback = 0;
    size_t unicode_bytes = 0;
    for (size_t variant = 0; variant < 2; ++variant) {
        MWXSceneQuickJSDomain *domain = font_contract_domain(fixture);
        if (domain == NULL) continue;
        const char *registered = variant ? "fonts/Renamed-Registered.ttf" : "fonts/Registered.ttf";
        const char *variable = variant ? "selectedFace" : "registeredFace";
        const char *target = variant ? "targetLayer" : "peer";
        const char *path = variant ? "'fonts/'+'Renamed-Regular.ttf'" : "'fonts/Probe-Regular.ttf'";
        char source[2048];
        snprintf(source, sizeof(source),
            "const %s=engine.registerAsset('%s');"
            "if(typeof %s!=='string'||%s!=='%s')throw new Error('registerAsset path');"
            "let clone;export function update(v){const %s=thisScene.getLayerByID(%s);"
            "if(v===1){const next=%s;thisLayer.font=next;"
            "if(typeof thisLayer.font!=='string'||thisLayer.font!==next||%s.font!==next)"
            "throw new Error('font same callback read');"
            "clone=thisScene.createLayer({text:'owned probe',font:thisLayer.font});"
            "if(typeof clone.font!=='string'||clone.font!==next)throw new Error('font clone');"
            "clone.font=%s;%s.font=%s;"
            "if(clone.font!=='%s'||thisLayer.font!=='%s')throw new Error('registered path reuse');}"
            "if(v===2){thisLayer.font=%s;clone.font=%s;}return thisScene.getLayerCount();}",
            variable, registered, variable, variable, registered, target,
            variant ? "8+9" : "17", path, target, variable, target, variable,
            registered, registered, variable, variable);
        const int before = fixture->failures;
        MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_owner_create(
            domain, source, strlen(source), 900, fixture->diagnostic, sizeof(fixture->diagnostic));
        fixture->failures += mwx_fixture_check(owner != NULL, "font String owner", fixture->diagnostic);
        fixture->failures += mwx_fixture_configure_owner_layer(owner, 17, "font String target");
        fixture->failures += mwx_fixture_update(owner, 900, 1, MWX_SCENE_QUICKJS_OK, 3,
            "String getter setter clone and registerAsset strict equality");
        size_t authored = 0, created = 0;
        char committed_font[1025] = {0};
        const size_t count = mwx_scene_quickjs_owner_layer_mutation_count(owner);
        for (size_t index = 0; index < count; ++index) {
            MWXSceneQuickJSLayerMutation mutation = {0};
            MWXSceneQuickJSResult result = mwx_scene_quickjs_owner_layer_mutation_at(
                owner, index, &mutation, fixture->diagnostic, sizeof(fixture->diagnostic));
            const int matches = result == MWX_SCENE_QUICKJS_OK && mutation.font != NULL
                && strcmp(mutation.font, registered) == 0;
            authored += matches && !mutation.dynamic && mutation.layer_id == 17
                && (mutation.fields & MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_FONT) != 0;
            created += matches && mutation.dynamic && strcmp(mutation.text, "owned probe") == 0;
            if (matches && !mutation.dynamic && mutation.layer_id == 17)
                memcpy(committed_font, mutation.font, strlen(mutation.font) + 1);
        }
        fixture->failures += mwx_fixture_check(count == 2 && authored == 1 && created == 1,
            "executed font paths reach authored and created mutation payloads", fixture->diagnostic);
        positive[variant] = fixture->failures == before;
        mwx_scene_quickjs_owner_commit_layer_mutations(owner);
        const int before_no_op = fixture->failures;
        // The host consumes authored mutations, then publishes the next frame's
        // runtime snapshot. Committing the C journal alone does not apply them.
        const double scale[3] = {1, 1, 1}, angles[3] = {0, 0, 0}, color[3] = {1, 1, 1};
        MWXSceneQuickJSResult snapshot = mwx_scene_quickjs_domain_begin_layer_snapshot(
            domain, 3, 0, fixture->diagnostic, sizeof(fixture->diagnostic));
        if (snapshot == MWX_SCENE_QUICKJS_OK)
            snapshot = mwx_scene_quickjs_domain_update_layer_runtime_fields(
                domain, 0, scale, angles, 0, 1, 1, 0, 1, "baseline", 8,
                committed_font, strlen(committed_font), 32, color,
                fixture->diagnostic, sizeof(fixture->diagnostic));
        if (snapshot == MWX_SCENE_QUICKJS_OK)
            snapshot = mwx_scene_quickjs_domain_reuse_layer_runtime_fields(
                domain, 1, fixture->diagnostic, sizeof(fixture->diagnostic));
        if (snapshot == MWX_SCENE_QUICKJS_OK)
            snapshot = mwx_scene_quickjs_domain_commit_layer_snapshot(
                domain, fixture->diagnostic, sizeof(fixture->diagnostic));
        fixture->failures += mwx_fixture_check(snapshot == MWX_SCENE_QUICKJS_OK,
            "consumed authored font reaches next runtime snapshot", fixture->diagnostic);
        mwx_scene_quickjs_domain_finalize_layer_snapshot(domain);
        fixture->failures += mwx_fixture_update(owner, 900, 2, MWX_SCENE_QUICKJS_OK, 3,
            "same font String assignment after commit");
        fixture->failures += mwx_fixture_check(mwx_scene_quickjs_owner_layer_mutation_count(owner) == 0,
            "same font String emits no mutation", fixture->diagnostic);
        no_op[variant] = fixture->failures == before_no_op;
        mwx_scene_quickjs_owner_destroy(owner);
        mwx_scene_quickjs_domain_destroy(domain);
    }

    MWXSceneQuickJSDomain *domain = font_contract_domain(fixture);
    if (domain != NULL) {
        const int before = fixture->failures;
        const char *source =
            "export function update(v){const layer=thisLayer;"
            "const boundary='fonts/'+'é'.repeat(509);layer.font=boundary;"
            "const child=thisScene.createLayer({text:'boundary',font:boundary});"
            "if(layer.font!==boundary||child.font!==boundary)throw new Error('Unicode1024');"
            "let coercions=0;const forged={toString(){coercions++;return 'fonts/forged.ttf';}};"
            "const bad=['/fonts/absolute.ttf','../fonts/escape.ttf','fonts/../escape.ttf',"
            "'fonts\\\\bad.ttf','fonts/a\\0.ttf','fonts/'+'é'.repeat(510),forged,{path:'fonts/x.ttf'}];"
            "for(const path of bad){let a=false,b=false;try{layer.font=path;}catch(e){a=true;}"
            "try{thisScene.createLayer({text:'bad',font:path});}catch(e){b=true;}"
            "if(!a||!b||layer.font!==boundary||thisScene.getLayerCount()!==3)"
            "throw new Error('invalid font accepted');}"
            "let originalException=false;try{thisScene.createLayer({text:'bad getter',"
            "get font(){throw new Error('font accessor sentinel');}});}"
            "catch(e){originalException=e.message==='font accessor sentinel';}"
            "let nontext=false;try{thisScene.getLayerByID(42).font=boundary;}catch(e){nontext=true;}"
            "if(coercions!==0||!nontext||!originalException||thisScene.getLayerCount()!==3)"
            "throw new Error('font coercion target or original exception');return bad.length*2;}";
        MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_owner_create(
            domain, source, strlen(source), 901, fixture->diagnostic, sizeof(fixture->diagnostic));
        fixture->failures += mwx_fixture_configure_owner_layer(owner, 17, "font invalid input target");
        fixture->failures += mwx_fixture_update(owner, 901, 1, MWX_SCENE_QUICKJS_OK, 16,
            "font setter and creator reject unsafe paths and forged objects without coercion");
        char boundary[1025];
        memcpy(boundary, "fonts/", 6);
        for (size_t index = 6; index < 1024; index += 2) {
            boundary[index] = (char)0xc3; boundary[index + 1] = (char)0xa9;
        }
        boundary[1024] = '\0';
        size_t exact_paths = 0;
        const size_t count = mwx_scene_quickjs_owner_layer_mutation_count(owner);
        for (size_t index = 0; index < count; ++index) {
            MWXSceneQuickJSLayerMutation mutation = {0};
            MWXSceneQuickJSResult result = mwx_scene_quickjs_owner_layer_mutation_at(
                owner, index, &mutation, fixture->diagnostic, sizeof(fixture->diagnostic));
            if (result == MWX_SCENE_QUICKJS_OK && mutation.font != NULL
                && strcmp(mutation.font, boundary) == 0) {
                ++exact_paths;
                unicode_bytes = strlen(mutation.font);
            }
        }
        fixture->failures += mwx_fixture_check(count == 2 && exact_paths == 2 && unicode_bytes == 1024,
            "UTF8 byte boundary preserved in real font mutation payloads", fixture->diagnostic);
        invalid = fixture->failures == before;
        mwx_scene_quickjs_owner_destroy(owner);
        mwx_scene_quickjs_domain_destroy(domain);
    }

    domain = font_contract_domain(fixture);
    if (domain != NULL) {
        const int before = fixture->failures;
        const char *source =
            "const face=engine.registerAsset('fonts/Registered.ttf');"
            "export function update(v){thisLayer.font='fonts/Transient.ttf';thisLayer.text='partial';"
            "const born=thisScene.createLayer({text:'partial child',font:thisLayer.font});"
            "born.font=face;throw new Error('deliberate font bundle failure');}";
        MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_owner_create(
            domain, source, strlen(source), 902, fixture->diagnostic, sizeof(fixture->diagnostic));
        fixture->failures += mwx_fixture_configure_owner_layer(owner, 17, "font rollback target");
        fixture->failures += mwx_fixture_update(owner, 902, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
            "font text and birth bundle throws");
        fixture->failures += mwx_fixture_check(mwx_scene_quickjs_owner_layer_mutation_count(owner) == 0,
            "failed font bundle has no pending mutation", fixture->diagnostic);
        const char *observer_source =
            "export function update(v){return thisLayer.font==='fonts/Baseline.ttf'&&"
            "thisLayer.text==='baseline'&&thisScene.getLayerCount()===2?1:0;}";
        MWXSceneQuickJSOwner *observer = mwx_scene_quickjs_owner_create(
            domain, observer_source, strlen(observer_source), 903,
            fixture->diagnostic, sizeof(fixture->diagnostic));
        fixture->failures += mwx_fixture_configure_owner_layer(observer, 17, "font rollback observer");
        fixture->failures += mwx_fixture_update(observer, 903, 1, MWX_SCENE_QUICKJS_OK, 1,
            "independent observer sees complete previous font text and catalog");
        rollback = fixture->failures == before;
        mwx_scene_quickjs_owner_destroy(observer);
        mwx_scene_quickjs_owner_destroy(owner);
        mwx_scene_quickjs_domain_destroy(domain);
    }
    printf("MWX_FONT_PATH_CONTRACT {\"positive\":%d,\"renamed\":%d,\"sameValueNoMutation\":%d,"
        "\"invalidInputs\":%d,\"unicodeBytes\":%zu,\"rollback\":%d}\n",
        positive[0], positive[1], no_op[0] && no_op[1], invalid, unicode_bytes, rollback);
}

void mwx_fixture_authored_layer_mutation_cases(MWXSceneScriptQuickJSFixture *fixture) {
    font_path_contract_cases(fixture);
    fixture->static_setter = mwx_scene_quickjs_owner_create(
        fixture->domain,
        "export function update(value){thisLayer.origin=new Vec3(1,2,3);return value;}",
        strlen("export function update(value){thisLayer.origin=new Vec3(1,2,3);return value;}"),
        45, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->static_setter != NULL, "static setter owner compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_configure_owner_layer(fixture->static_setter, 42, "static setter owner identity");
    fixture->failures += mwx_fixture_update(
        fixture->static_setter, 45, 1, MWX_SCENE_QUICKJS_OK, 1,
        "static layer transform setter accepted"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_layer_mutation_count(fixture->static_setter) == 1,
        "static layer transform mutation coalesced", ""
    );
    fixture->failures += mwx_fixture_layer_mutation(
        fixture->static_setter, 0, MWX_SCENE_QUICKJS_LAYER_MUTATION_UPSERT,
        0, MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ORIGIN,
        42, 2, "clock", "static layer transform snapshot"
    );

    // A layer property belongs to the layer itself: `thisObject` is the same
    // object as `thisLayer` (one object model, one mutation journal), and
    // `getChildren()` hands back ordinary handles for authored children.
    const char *property_object_source =
        "let child;"
        "export function init(){child=thisObject.getChildren()[0];}"
        "export function update(value){"
        "if(thisObject!==thisLayer)throw new Error('object identity');"
        "if(typeof thisObject.getAnimation!=='function')"
        "throw new Error('layer animation');"
        "let rejected=false;"
        "try{thisObject.getChildren(1);}catch(error){rejected=true;}"
        "if(!rejected)throw new Error('children arguments');"
        "const children=thisObject.getChildren();"
        "if(children.length!==1)throw new Error('child count');"
        "if(child.id!==42||child.name!=='C1')throw new Error('child identity');"
        "if(thisScene.getLayer('C1').getChildren().length!==0)"
        "throw new Error('leaf children');"
        "thisObject.getAnimation().play();"
        "thisObject.visible=false;thisLayer.alpha=0.5;"
        "child.visible=false;child.color=new Vec3(0.25,0.5,0.75);"
        "return value;}";
    fixture->property_object = mwx_scene_quickjs_owner_create(
        fixture->domain, property_object_source, strlen(property_object_source),
        47, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->property_object != NULL, "property object compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->property_object, 17, "property object owner identity"
    );
    char scope_diagnostic[512] = {0};
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_set_property_object_scope(
            fixture->property_object, 1, scope_diagnostic, sizeof(scope_diagnostic)
        ) == MWX_SCENE_QUICKJS_OK,
        "property object scope", scope_diagnostic
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_configure_current_animation(
            fixture->property_object, 1, scope_diagnostic, sizeof(scope_diagnostic)
        ) == MWX_SCENE_QUICKJS_OK,
        "property object animation configure", scope_diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->property_object, 47, 1, MWX_SCENE_QUICKJS_OK, 1,
        "property object and child writes"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_layer_mutation_count(fixture->property_object) == 2,
        "property object mutations coalesce per layer", ""
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_animation_command_count(fixture->property_object) == 1,
        "property object keeps the current property animation", ""
    );
    fixture->failures += mwx_fixture_layer_mutation(
        fixture->property_object, 0, MWX_SCENE_QUICKJS_LAYER_MUTATION_UPSERT, 0,
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_VISIBILITY
            | MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ALPHA,
        17, 0, "", "thisObject and thisLayer share one layer mutation"
    );
    fixture->failures += mwx_fixture_layer_mutation(
        fixture->property_object, 1, MWX_SCENE_QUICKJS_LAYER_MUTATION_UPSERT, 0,
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_VISIBILITY
            | MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_COLOR,
        42, 2, "clock", "getChildren handle writes the child layer"
    );

    // Component properties keep the property-object handle: only layer and
    // text properties belong to the layer itself.
    const char *component_object_source =
        "export function update(value){"
        "if(thisObject===thisLayer)throw new Error('component scope');"
        "if(typeof thisObject.getAnimation!=='function')"
        "throw new Error('component animation');"
        "return value;}";
    fixture->component_object = mwx_scene_quickjs_owner_create(
        fixture->domain, component_object_source, strlen(component_object_source),
        48, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->component_object != NULL, "component object compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->component_object, 42, "component object owner identity"
    );
    fixture->failures += mwx_fixture_update(
        fixture->component_object, 48, 1, MWX_SCENE_QUICKJS_OK, 1,
        "component property object keeps its own handle"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_layer_mutation_count(fixture->component_object) == 0,
        "component property object writes nothing", ""
    );

    const char *authored_self_destroy_source =
        "export function update(value){"
        "thisScene.destroyLayer('C1');return value;}";
    MWXSceneQuickJSResult authored_self_destroy_creation =
        MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    fixture->authored_self_destroy =
        mwx_scene_quickjs_owner_create_effectful_bool_with_budget(
            fixture->domain, authored_self_destroy_source,
            strlen(authored_self_destroy_source), 145, 100000,
            &authored_self_destroy_creation, fixture->diagnostic, sizeof(fixture->diagnostic)
        );
    fixture->failures += mwx_fixture_check(
        fixture->authored_self_destroy != NULL &&
            authored_self_destroy_creation == MWX_SCENE_QUICKJS_OK,
        "authored self destroy compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->authored_self_destroy, 42, "authored self destroy owner identity"
    );
    fixture->failures += mwx_fixture_update_effectful_bool(
        fixture->authored_self_destroy, 145, 1, MWX_SCENE_QUICKJS_OK, 1,
        "authored self destroy by name"
    );
    fixture->failures += mwx_fixture_layer_mutation(
        fixture->authored_self_destroy, 0, MWX_SCENE_QUICKJS_LAYER_MUTATION_DESTROY,
        0, 0, 42, 2, "clock", "authored self destroy snapshot"
    );
    mwx_scene_quickjs_owner_commit_layer_mutations(fixture->authored_self_destroy);

    const char *authored_peer_destroy_source =
        "export function update(value){"
        "if(thisScene.destroyLayer('anchor')!==true)throw new Error('return');"
        "if(thisScene.getLayer('anchor')===null)throw new Error('not deferred');"
        "return value;}";
    MWXSceneQuickJSResult authored_peer_destroy_creation =
        MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    fixture->authored_peer_destroy =
        mwx_scene_quickjs_owner_create_effectful_bool_with_budget(
            fixture->domain, authored_peer_destroy_source,
            strlen(authored_peer_destroy_source), 146, 100000,
            &authored_peer_destroy_creation, fixture->diagnostic, sizeof(fixture->diagnostic)
        );
    fixture->failures += mwx_fixture_check(
        fixture->authored_peer_destroy != NULL &&
            authored_peer_destroy_creation == MWX_SCENE_QUICKJS_OK,
        "authored peer destroy compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->authored_peer_destroy, 42, "authored peer destroy owner identity"
    );
    fixture->failures += mwx_fixture_update_effectful_bool(
        fixture->authored_peer_destroy, 146, 1, MWX_SCENE_QUICKJS_OK, 1,
        "authored peer destroy deferred and returns true"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_layer_mutation_count(
            fixture->authored_peer_destroy
        ) == 1,
        "authored peer destroy stages one tombstone", ""
    );

    fixture->failures += mwx_fixture_layer_mutation(
        fixture->authored_peer_destroy, 0, MWX_SCENE_QUICKJS_LAYER_MUTATION_DESTROY,
        0, 0, 17, 0, "", "authored peer destroy target snapshot"
    );
    mwx_scene_quickjs_owner_discard_layer_mutations(fixture->authored_peer_destroy);

    const char *authored_peer_source =
        "const replacement=engine.registerAsset('fonts/replacement.ttf');"
        "export function update(value){"
        "const layer=thisScene.getLayerByID(17);"
        "layer.origin=new Vec3(7,8,9);"
        "layer.scale=new Vec3(2,4,6);"
        "layer.angles=new Vec3(10,20,30);"
        "layer.visible=false;layer.text='~';layer.font=replacement;layer.pointsize=99;"
        "if(layer.origin.x!==7||layer.origin.y!==8||layer.origin.z!==9||"
        "layer.scale.x!==2||layer.scale.y!==4||layer.scale.z!==6||"
        "layer.angles.x!==10||layer.angles.y!==20||layer.angles.z!==30||"
        "layer.visible!==false||layer.text!=='~'||layer.pointsize!==99)"
        "throw new Error('authored peer read-your-writes');"
        "let forgedFontRejected=false,readonlySizeRejected=false;"
        "try{layer.font='../replacement';}catch(error){forgedFontRejected=true;}"
        "try{layer.size=new Vec2(1,2);}catch(error){readonlySizeRejected=true;}"
        "if(!forgedFontRejected||!readonlySizeRejected||"
        "typeof layer.alpha!=='number'||typeof layer.solid!=='boolean')"
        "throw new Error('unsupported authored fields opened');"
        "return value;}";
    fixture->authored_peer = mwx_scene_quickjs_owner_create(
        fixture->domain, authored_peer_source, strlen(authored_peer_source),
        56, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->authored_peer != NULL, "authored peer compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->authored_peer, 42, "authored peer owner identity"
    );
    fixture->failures += mwx_fixture_update(
        fixture->authored_peer, 56, 1, MWX_SCENE_QUICKJS_OK, 1,
        "authored peer target-indexed staging"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_layer_mutation_count(fixture->authored_peer) == 1,
        "authored peer mutation coalesced by target", ""
    );
    const uint32_t authored_peer_fields =
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ORIGIN |
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_SCALE |
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ANGLES |
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_VISIBILITY |
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_TEXT |
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_FONT |
        MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_POINT_SIZE;
    fixture->failures += mwx_fixture_layer_mutation(
        fixture->authored_peer, 0, MWX_SCENE_QUICKJS_LAYER_MUTATION_UPSERT,
        0, authored_peer_fields, 17, 0, "~",
        "authored peer staged snapshot"
    );
    MWXSceneQuickJSLayerMutation authored_peer_mutation = {0};
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_layer_mutation_at(
            fixture->authored_peer, 0, &authored_peer_mutation,
            fixture->diagnostic, sizeof(fixture->diagnostic)
        ) == MWX_SCENE_QUICKJS_OK &&
            authored_peer_mutation.origin[0] == 7 &&
            authored_peer_mutation.origin[1] == 8 &&
            authored_peer_mutation.origin[2] == 9 &&
            authored_peer_mutation.scale[0] == 2 &&
            authored_peer_mutation.scale[1] == 4 &&
            authored_peer_mutation.scale[2] == 6 &&
            authored_peer_mutation.angles[0] == 10 &&
            authored_peer_mutation.angles[1] == 20 &&
            authored_peer_mutation.angles[2] == 30 &&
            authored_peer_mutation.visible == 0 &&
            authored_peer_mutation.point_size == 99 &&
            strcmp(authored_peer_mutation.font, "fonts/replacement.ttf") == 0,
        "authored peer staged values", fixture->diagnostic
    );

    const char *authored_observer_source =
        "export function update(value){const layer=thisScene.getLayerByID(17);"
        "return layer.origin.x===1&&layer.origin.y===2&&layer.origin.z===3&&"
        "layer.scale.x===1&&layer.scale.y===1&&layer.scale.z===1&&"
        "layer.angles.x===0&&layer.angles.y===0&&layer.angles.z===0&&"
        "layer.visible===true&&layer.text===''&&layer.pointsize===32?1:0;}";
    fixture->authored_observer = mwx_scene_quickjs_owner_create(
        fixture->domain, authored_observer_source, strlen(authored_observer_source),
        57, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->authored_observer != NULL, "authored observer compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->authored_observer, 42, "authored observer owner identity"
    );
    fixture->failures += mwx_fixture_update(
        fixture->authored_observer, 57, 1, MWX_SCENE_QUICKJS_OK, 1,
        "authored staging leaves shared record unchanged"
    );

    const char *missing_target_rollback_source =
        "export function update(value){const layer=thisScene.getLayerByID(17);"
        "layer.origin=new Vec3(30,31,32);layer.text='pending';"
        "thisScene.getLayer('missing-authored-target').scale=new Vec3(9,9,9);"
        "return value;}";
    fixture->missing_target_rollback = mwx_scene_quickjs_owner_create(
        fixture->domain, missing_target_rollback_source,
        strlen(missing_target_rollback_source),
        58, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->missing_target_rollback != NULL,
        "missing authored target rollback compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->missing_target_rollback, 42,
        "missing authored target rollback owner identity"
    );
    fixture->failures += mwx_fixture_update(
        fixture->missing_target_rollback, 58, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "missing authored target rolls back whole callback"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_layer_mutation_count(fixture->missing_target_rollback) == 0,
        "missing authored target exposes no staged mutation", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->authored_observer, 57, 1, MWX_SCENE_QUICKJS_OK, 1,
        "missing authored target leaves shared record unchanged"
    );

    const char *oversized_authored_text_source =
        "export function update(value){"
        "thisScene.getLayerByID(17).text='x'.repeat(4097);return value;}";
    fixture->oversized_authored_text = mwx_scene_quickjs_owner_create(
        fixture->domain, oversized_authored_text_source,
        strlen(oversized_authored_text_source),
        59, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->oversized_authored_text != NULL,
        "oversized authored text compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->oversized_authored_text, 42, "oversized authored text owner identity"
    );
    fixture->failures += mwx_fixture_update(
        fixture->oversized_authored_text, 59, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "oversized authored text rejected"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_layer_mutation_count(fixture->oversized_authored_text) == 0,
        "oversized authored text leaves no staged mutation", fixture->diagnostic
    );

    const char *nul_authored_text_source =
        "export function update(value){thisScene.getLayerByID(17).text="
        "String.fromCharCode(97,0,98);return value;}";
    fixture->nul_authored_text = mwx_scene_quickjs_owner_create(
        fixture->domain, nul_authored_text_source, strlen(nul_authored_text_source),
        64, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->nul_authored_text != NULL, "NUL authored text compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->nul_authored_text, 42, "NUL authored text owner identity"
    );
    fixture->failures += mwx_fixture_update(
        fixture->nul_authored_text, 64, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "NUL authored text rejected"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_layer_mutation_count(fixture->nul_authored_text) == 0,
        "NUL authored text leaves no staged mutation", fixture->diagnostic
    );

    const char *nontext_authored_text_source =
        "export function update(value){"
        "thisScene.getLayerByID(42).text='invalid';return value;}";
    fixture->nontext_authored_text = mwx_scene_quickjs_owner_create(
        fixture->domain, nontext_authored_text_source,
        strlen(nontext_authored_text_source),
        65, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->nontext_authored_text != NULL,
        "non-text authored text compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->nontext_authored_text, 17, "non-text authored text owner identity"
    );
    fixture->failures += mwx_fixture_update(
        fixture->nontext_authored_text, 65, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "non-text authored text rejected before Swift transaction"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_layer_mutation_count(fixture->nontext_authored_text) == 0
            && mwx_scene_quickjs_owner_layer_mutation_count(fixture->authored_peer) == 1,
        "bad authored text owner preserves disjoint valid owner", fixture->diagnostic
    );

    const char *nonfinite_authored_source =
        "export function update(value){const layer=thisScene.getLayerByID(17);"
        "layer.text='pending';layer.scale=new Vec3(4,5,6);"
        "layer.scale=new Vec3(1,NaN,1);"
        "if(layer.scale.y!==5)throw new Error('valid candidate lost');"
        "layer.origin=new Vec3(Infinity,2,3);"
        "layer.angles=new Vec3(1,2,-Infinity);return value;}";
    fixture->nonfinite_authored = mwx_scene_quickjs_owner_create(
        fixture->domain, nonfinite_authored_source, strlen(nonfinite_authored_source),
        60, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->nonfinite_authored != NULL, "nonfinite authored compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_owner_layer(
        fixture->nonfinite_authored, 42, "nonfinite authored owner identity"
    );
    fixture->failures += mwx_fixture_update(
        fixture->nonfinite_authored, 60, 1, MWX_SCENE_QUICKJS_OK, 1,
        "nonfinite authored transform rejects only its assignment"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_layer_mutation_count(fixture->nonfinite_authored) == 1,
        "valid authored changes survive invalid transform", fixture->diagnostic
    );
    MWXSceneQuickJSLayerMutation finite_authored = {0};
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_layer_mutation_at(fixture->nonfinite_authored, 0,
            &finite_authored, fixture->diagnostic, sizeof(fixture->diagnostic)) == MWX_SCENE_QUICKJS_OK
            && finite_authored.fields == (MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_TEXT
                | MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_SCALE)
            && finite_authored.scale[0] == 4 && finite_authored.scale[1] == 5
            && finite_authored.scale[2] == 6,
        "only finite authored payload crosses C bridge", fixture->diagnostic
    );
    mwx_scene_quickjs_owner_discard_layer_mutations(fixture->nonfinite_authored);
    fixture->failures += mwx_fixture_update(
        fixture->authored_observer, 57, 1, MWX_SCENE_QUICKJS_OK, 1,
        "invalid authored mutations leave shared record unchanged"
    );

    MWXSceneQuickJSDomain *finite_domain = mwx_scene_quickjs_domain_create(
        2 * 1024 * 1024, 512 * 1024, 100000, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(finite_domain != NULL, "finite transform domain", fixture->diagnostic);
    fixture->failures += mwx_fixture_configure_layers(finite_domain);
    const char *finite_source =
        "let layer;export function update(v){"
        "if(v===1){layer=thisScene.createLayer({text:'base'});return v;}"
        "if(v===2){for(let p of ['origin','scale','angles']){"
        "layer[p]={x:'2',y:3,z:4};"
        "for(let a of ['x','y','z'])for(let bad of [NaN,Infinity,-Infinity]){"
        "let next=new Vec3(90,91,92);next[a]=bad;layer[p]=next;"
        "let got=layer[p];if(got.x!==2||got.y!==3||got.z!==4)"
        "throw new Error('assignment not atomic');}}layer.text='next';return v;}"
        "if(v===3){if(layer.text!=='base'||layer.origin.x!==0||"
        "layer.scale.y!==1||layer.angles.z!==0)throw new Error('discard leak');"
        "return v;}"
        "if(v===7){let seen='';layer.scale={"
        "get x(){seen+='x';return NaN;},get y(){seen+='y';return Infinity;},"
        "get z(){seen+='z';return -Infinity;}};"
        "if(seen!=='xyz')throw new Error('getter skipped');return v;}"
        "if(v===8){layer.origin=new Vec3(NaN);"
        "if(layer.text!=='next'||layer.origin.x!==2||layer.scale.y!==3||"
        "layer.angles.z!==4)throw new Error('commit lost');return v;}"
        "return v;}";
    MWXSceneQuickJSOwner *finite_owner = mwx_scene_quickjs_owner_create(
        finite_domain, finite_source, strlen(finite_source), 820,
        fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(finite_owner != NULL, "finite transform owner", fixture->diagnostic);
    fixture->failures += mwx_fixture_configure_owner_layer(finite_owner, 17, "finite transform target");
    fixture->failures += mwx_fixture_update(finite_owner, 820, 1, MWX_SCENE_QUICKJS_OK, 1,
        "finite layer seed");
    mwx_scene_quickjs_owner_commit_layer_mutations(finite_owner);
    fixture->failures += mwx_fixture_update(finite_owner, 820, 2, MWX_SCENE_QUICKJS_OK, 2,
        "all transform axes reject numeric nonfinite without losing valid siblings");
    MWXSceneQuickJSLayerMutation finite_dynamic = {0};
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_layer_mutation_count(finite_owner) == 1
            && mwx_scene_quickjs_owner_layer_mutation_at(finite_owner, 0,
                &finite_dynamic, fixture->diagnostic, sizeof(fixture->diagnostic)) == MWX_SCENE_QUICKJS_OK
            && finite_dynamic.origin[0] == 2 && finite_dynamic.origin[1] == 3
            && finite_dynamic.origin[2] == 4 && finite_dynamic.scale[0] == 2
            && finite_dynamic.scale[1] == 3 && finite_dynamic.scale[2] == 4
            && finite_dynamic.angles[0] == 2 && finite_dynamic.angles[1] == 3
            && finite_dynamic.angles[2] == 4,
        "only complete finite dynamic transforms publish", fixture->diagnostic
    );
    mwx_scene_quickjs_owner_discard_layer_mutations(finite_owner);
    fixture->failures += mwx_fixture_update(finite_owner, 820, 3, MWX_SCENE_QUICKJS_OK, 3,
        "outer discard still restores complete previous current");
    fixture->failures += mwx_fixture_update(finite_owner, 820, 7, MWX_SCENE_QUICKJS_OK, 7,
        "invalid-only assignment preserves current");
    fixture->failures += mwx_fixture_check(mwx_scene_quickjs_owner_layer_mutation_count(finite_owner) == 0,
        "invalid-only assignment consumes no mutation", fixture->diagnostic);
    fixture->failures += mwx_fixture_update(finite_owner, 820, 2, MWX_SCENE_QUICKJS_OK, 2,
        "finite candidates can retry after discard");
    mwx_scene_quickjs_owner_commit_layer_mutations(finite_owner);
    fixture->failures += mwx_fixture_update(finite_owner, 820, 8, MWX_SCENE_QUICKJS_OK, 8,
        "later invalid transform preserves committed finite state");
    fixture->failures += mwx_fixture_check(mwx_scene_quickjs_owner_layer_mutation_count(finite_owner) == 0,
        "invalid assignment after commit consumes no mutation", fixture->diagnostic);
    mwx_scene_quickjs_owner_destroy(finite_owner);
    mwx_scene_quickjs_domain_destroy(finite_domain);

    // A hard callback failure disables its owner. Use fresh owners and read
    // committed authored state through an independent observer after each one.
    const char *invalid_transform_cases[] = {
        "layer.scale={x:NaN,get y(){throw new Error('late getter');},z:1};",
        "layer.scale={x:NaN,y:undefined,z:1};",
        "layer.scale={x:NaN,y:Symbol('bad'),z:1};",
        "layer.scale={x:NaN,y:'bad',z:1};",
        "layer.scale={x:1,z:1};",
        "layer.origin=new Vec3(NaN);throw new Error('explicit error');",
        "layer.color=new Vec3(NaN);",
        "thisScene.createLayer({text:'bad',scale:new Vec3(NaN)});"
    };
    for (size_t invalid_case = 0; invalid_case <
            sizeof(invalid_transform_cases) / sizeof(invalid_transform_cases[0]);
            ++invalid_case) {
        MWXSceneQuickJSDomain *rejection_domain = mwx_scene_quickjs_domain_create(
            2 * 1024 * 1024, 512 * 1024, 100000, fixture->diagnostic, sizeof(fixture->diagnostic));
        fixture->failures += mwx_fixture_configure_layers(rejection_domain);
        char rejection_source[1024];
        snprintf(rejection_source, sizeof(rejection_source),
            "export function update(v){const layer=thisLayer;layer.text='leak';%sreturn v;}",
            invalid_transform_cases[invalid_case]);
        MWXSceneQuickJSOwner *rejection_owner = mwx_scene_quickjs_owner_create(
            rejection_domain, rejection_source, strlen(rejection_source), 821,
            fixture->diagnostic, sizeof(fixture->diagnostic));
        fixture->failures += mwx_fixture_configure_owner_layer(rejection_owner, 17, "hard rejection target");
        fixture->failures += mwx_fixture_update(rejection_owner, 821, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
            invalid_transform_cases[invalid_case]);
        fixture->failures += mwx_fixture_check(mwx_scene_quickjs_owner_layer_mutation_count(rejection_owner) == 0,
            "hard rejection discards valid prefix", fixture->diagnostic);
        const char *observer_source =
            "export function update(v){if(thisLayer.text!==''||thisLayer.scale.y!==1)"
            "throw new Error('failed owner leaked');return v;}";
        MWXSceneQuickJSOwner *rejection_observer = mwx_scene_quickjs_owner_create(
            rejection_domain, observer_source, strlen(observer_source), 822,
            fixture->diagnostic, sizeof(fixture->diagnostic));
        fixture->failures += mwx_fixture_configure_owner_layer(rejection_observer, 17, "hard rejection observer");
        fixture->failures += mwx_fixture_update(rejection_observer, 822, 1, MWX_SCENE_QUICKJS_OK, 1,
            "hard rejection preserves independent current state");
        mwx_scene_quickjs_owner_destroy(rejection_observer);
        mwx_scene_quickjs_owner_destroy(rejection_owner);
        mwx_scene_quickjs_domain_destroy(rejection_domain);
    }


    fixture->static_visible = mwx_scene_quickjs_owner_create(
        fixture->domain,
        "export function update(value){thisLayer.visible=false;return value;}",
        strlen("export function update(value){thisLayer.visible=false;return value;}"),
        46, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->static_visible != NULL, "static visible owner compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_configure_owner_layer(fixture->static_visible, 42, "static visible owner identity");
    fixture->failures += mwx_fixture_update(
        fixture->static_visible, 46, 1, MWX_SCENE_QUICKJS_OK, 1,
        "static layer visibility setter accepted"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_layer_mutation_count(fixture->static_visible) == 1,
        "static layer visibility mutation coalesced", ""
    );
    fixture->failures += mwx_fixture_layer_mutation(
        fixture->static_visible, 0, MWX_SCENE_QUICKJS_LAYER_MUTATION_UPSERT,
        0, MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_VISIBILITY,
        42, 2, "clock", "static layer visibility snapshot"
    );
    MWXSceneQuickJSLayerMutation static_visibility_mutation = {0};
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_layer_mutation_at(
            fixture->static_visible, 0, &static_visibility_mutation,
            fixture->diagnostic, sizeof(fixture->diagnostic)
        ) == MWX_SCENE_QUICKJS_OK &&
            static_visibility_mutation.visible == 0,
        "static layer visibility value", fixture->diagnostic
    );

}
