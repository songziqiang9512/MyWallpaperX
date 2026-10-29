#include "SceneQuickJSInternal.h"
#include <stdlib.h>
#include <string.h>

MWXSceneQuickJSOwner *mwx_scene_quickjs_text_transaction_owner(MWXSceneQuickJSOwner *owner) {
    return owner && owner->provisional_text_creator ? owner->provisional_text_creator : owner;
}

bool mwx_scene_quickjs_text_clone_can_begin(MWXSceneQuickJSOwner *owner, uint64_t identity) {
    if (!owner || identity == 0 || identity > owner->domain->authored_layer_count) return false;
    MWXSceneQuickJSDomain *domain = owner->domain;
    MWXSceneQuickJSTextTemplate *item = domain->layers[identity - 1].text_template;
    return item && item->inputs_available && domain->callback_active && domain->active_owner == owner &&
        !owner->teardown_started && !owner->text_clone_failed && !domain->interrupted && domain->interrupt_budget &&
        !JS_HasException(domain->context) && !mwx_scene_quickjs_owner_has_job_residue(owner) &&
        (item->kind != 3 || domain->text_clone_depth == 0);
}

typedef struct {
    MWXSceneQuickJSOwner *active_owner, *module_owner;
    JSValue engine, layer, scene, object;
    MWXSceneQuickJSFrameInput frame;
    uint64_t epoch;
    MWXSceneQuickJSParticleEmission particle_emission;
    MWXSceneQuickJSParticleBoundary particle_boundary;
    void *particle_opaque;
    bool callback_active, frame_active, value_only;
} TextCloneActivation;

static TextCloneActivation suspend_parent(MWXSceneQuickJSDomain *domain) {
    TextCloneActivation scope = {.active_owner=domain->active_owner, .module_owner=domain->module_owner,
        .engine=domain->active_engine, .layer=domain->active_layer, .scene=domain->active_scene,
        .object=domain->active_object, .frame=domain->active_frame_input, .epoch=domain->callback_epoch,
        .callback_active=domain->callback_active, .frame_active=domain->frame_input_active,
        .value_only=domain->value_only_guard_active, .particle_emission=domain->particle_emission,
        .particle_boundary=domain->particle_boundary, .particle_opaque=domain->particle_emission_opaque};
    // Transfer these roots into the lexical scope; there is no second VM state.
    domain->active_engine = domain->active_layer = domain->active_scene = domain->active_object = JS_UNDEFINED;
    domain->active_owner = domain->module_owner = NULL;
    domain->callback_active = domain->frame_input_active = domain->value_only_guard_active = false;
    memset(&domain->active_frame_input, 0, sizeof(domain->active_frame_input));
    domain->text_clone_depth = 1;
    // The cadence owns one particle transaction. Nested end/discard must not
    // clear its parent prefix, and no child emit may enter Swift preview.
    // Active/native work/limit/reservations stay shared and are never rewound.
    domain->particle_emission = NULL;
    domain->particle_boundary = NULL;
    domain->particle_emission_opaque = NULL;
    return scope;
}

static void restore_parent(MWXSceneQuickJSDomain *domain, const TextCloneActivation *scope) {
    JS_FreeValue(domain->context, domain->active_engine);
    JS_FreeValue(domain->context, domain->active_layer);
    JS_FreeValue(domain->context, domain->active_scene);
    JS_FreeValue(domain->context, domain->active_object);
    domain->active_engine=scope->engine; domain->active_layer=scope->layer;
    domain->active_scene=scope->scene; domain->active_object=scope->object;
    domain->active_owner=scope->active_owner; domain->module_owner=scope->module_owner;
    domain->callback_active=scope->callback_active; domain->callback_epoch=scope->epoch;
    domain->frame_input_active=scope->frame_active; domain->active_frame_input=scope->frame;
    domain->value_only_guard_active=scope->value_only;
    domain->particle_emission=scope->particle_emission;
    domain->particle_boundary=scope->particle_boundary;
    domain->particle_emission_opaque=scope->particle_opaque;
    // Remaining fuel and sticky interruption are shared with the outer callback.
    domain->text_clone_depth=0;
}

static bool configure_child(MWXSceneQuickJSOwner *child, MWXSceneQuickJSTextTemplate *item, uint32_t index) {
    MWXSceneQuickJSDomain *domain=child->domain;
    MWXSceneQuickJSLayerAccessHandle *reference=JS_GetOpaque(child->material_function_layer, domain->layer_handle_class_id);
    if (!reference || reference->domain != domain) return false;
    child->target_layer_index=index; child->target_layer_configured=true;
    reference->layer_index=index; reference->owner_target=false;
    reference->expected_layer_id=child->text_clone_layer_id;
    // createLayer(text/font/...) creates a fresh text leaf, not a copy of the
    // source layer's effect or timeline consumers. thisObject is that leaf.
    child->property_object_is_layer=true;
    if (item->alias_count) {
        child->dynamic_image_aliases=calloc(item->alias_count,sizeof(*child->dynamic_image_aliases));
        if (!child->dynamic_image_aliases) return false;
        // These are already normalized identities from the original prepare owner.
        child->dynamic_image_alias_count=item->alias_count;
        for(uint32_t i=0;i<item->alias_count;++i) {
            child->dynamic_image_aliases[i].authored_path=strdup(item->aliases[i].authored_path);
            child->dynamic_image_aliases[i].model_path=strdup(item->aliases[i].model_path);
            if(!child->dynamic_image_aliases[i].authored_path || !child->dynamic_image_aliases[i].model_path) return false;
        }
    }
    return mwx_scene_quickjs_text_exports_supported(child);
}

static bool unsupported_init_contribution(MWXSceneQuickJSOwner *child) {
    // No target may be silently reinterpreted as the creator's target. These
    // original command buffers remain private to the child until a future lane
    // can express their complete target in the creator bundle.
    return child->material_function_count || child->material_function_overflow ||
        child->animation_command_count || child->animation_command_overflow ||
        child->media_playback_command_count || child->media_playback_command_overflow ||
        child->texture_animation_command_count || child->texture_animation_command_overflow ||
        child->particle_playback_command_count || child->particle_playback_command_overflow ||
        child->puppet_animation_command_count || child->puppet_animation_command_overflow ||
        child->layer_mutation_overflow || child->puppet_bone_mutation_count || child->storage_mutation_count || child->storage_mutation_overflow ||
        child->audio_registration_count || child->video_ended_callback_count || child->text_clone_failed;
}

bool mwx_scene_quickjs_activate_text_clone(MWXSceneQuickJSOwner *creator, uint32_t index, uint64_t identity) {
    if (!mwx_scene_quickjs_text_clone_can_begin(creator,identity)) return false;
    MWXSceneQuickJSDomain *domain=creator->domain;
    MWXSceneQuickJSTextTemplate *item=domain->layers[identity-1].text_template;
    MWXSceneQuickJSLayerRecord *record=&domain->layers[index];
    record->text_template_identity=identity;
    if(item->kind!=3) return true;
    if (!mwx_scene_quickjs_domain_charge_work(domain,
        item->bytecode_length + item->input_length + item->properties_length + domain->user_properties_json_length + 1)) {
        creator->text_clone_failed=true;
        return false;
    }
    JSContext *context=domain->context;
    // The engine cache may be replaced during the nested bind. Own the bytes
    // for this lexical activation rather than borrowing its mutable cache.
    size_t user_length=domain->user_properties_json_length;
    char *user=malloc(user_length+1);
    if(!user) { creator->text_clone_failed=true; return false; }
    if(user_length)memcpy(user,domain->user_properties_json,user_length);
    user[user_length]=0;
    TextCloneActivation scope=suspend_parent(domain);
    JSValue module=JS_ReadObject(context,item->bytecode,item->bytecode_length,JS_READ_OBJ_BYTECODE);
    MWXSceneQuickJSOwner *child=NULL;
    MWXSceneQuickJSResult result=MWX_SCENE_QUICKJS_EXCEPTION;
    if(!JS_IsException(module) && JS_ResolveModule(context,module)==0)
        child=mwx_scene_quickjs_create_prepared_text_owner(domain,module,item->generation,&result,NULL,0);
    JS_FreeValue(context,module);
    if(child && result==MWX_SCENE_QUICKJS_OK) {
        child->provisional_text_creator=creator;
        child->text_clone_template_identity=identity;
        child->text_clone_creator_identity=creator->identity;
        child->text_clone_layer_id=record->layer_id;
        record->text_property_owner_identity=child->identity;
        // Module-time host attempts may have been caught by author JS before
        // provisional_text_creator existed. Check before init resets its flags.
        if(!configure_child(child,item,index) || unsupported_init_contribution(child))
            result=MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    char output[MWX_SCENE_QUICKJS_MAX_LAYER_TEXT+1];size_t output_length=0;uint32_t did=0;
    if(child && result==MWX_SCENE_QUICKJS_OK && !domain->interrupted && domain->interrupt_budget)
        result=mwx_scene_quickjs_owner_initialize_string(child,item->generation,item->current_input,item->input_length,
            &scope.frame,item->script_properties,item->properties_length,user,user_length,output,sizeof(output),&output_length,&did,NULL,0);
    bool success=child && result==MWX_SCENE_QUICKJS_OK && !unsupported_init_contribution(child) && !domain->interrupted;
    char *text=success?strdup(output):NULL;
    if(success && !text)success=false;
    if(success) {
        free(record->text);record->text=text;
        if(creator->text_clone_children_tail)creator->text_clone_children_tail->text_clone_next=child;
        else creator->text_clone_children=child;
        creator->text_clone_children_tail=child;
    }else {
        creator->text_clone_failed=true;
        if(child) { child->provisional_text_creator=NULL; mwx_scene_quickjs_owner_destroy(child); }
        record->text_property_owner_identity=0;
    }
    // Entry was exception/job-free; errors here belong only to child work.
    if(JS_HasException(context)) { JSValue error=JS_GetException(context);JS_FreeValue(context,error); }
    restore_parent(domain,&scope);
    free(user);
    return success;
}

static bool clone_layer_alive(MWXSceneQuickJSOwner *child) {
    MWXSceneQuickJSDomain *domain=child->domain;
    if(!child->target_layer_configured || child->target_layer_index>=domain->layer_count)return false;
    MWXSceneQuickJSLayerRecord *record=&domain->layers[child->target_layer_index];
    return record->configured && !record->destroyed && record->layer_id==child->text_clone_layer_id &&
        record->owner_identity==child->text_clone_creator_identity && record->text_property_owner_identity==child->identity;
}

void mwx_scene_quickjs_finish_text_clones(MWXSceneQuickJSOwner *creator, bool committing) {
    if(!creator)return;
    MWXSceneQuickJSDomain *domain=creator->domain;
    MWXSceneQuickJSOwner *child=creator->text_clone_children;
    creator->text_clone_children=creator->text_clone_children_tail=NULL;
    while(child) {
        MWXSceneQuickJSOwner *next=child->text_clone_next;
        child->text_clone_next=NULL;
        child->provisional_text_creator=NULL;
        if(committing && !creator->text_clone_failed && clone_layer_alive(child)) {
            mwx_scene_quickjs_owner_commit_layer_mutations(child);
            if(domain->committed_text_clone_tail)domain->committed_text_clone_tail->text_clone_next=child;
            else domain->committed_text_clone_head=child;
            domain->committed_text_clone_tail=child;
        }else {
            if(child->target_layer_configured && child->target_layer_index<domain->layer_count &&
                domain->layers[child->target_layer_index].text_property_owner_identity==child->identity)
                domain->layers[child->target_layer_index].text_property_owner_identity=0;
            mwx_scene_quickjs_owner_destroy(child);
        }
        child=next;
    }
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_take_committed_text_clone(
    MWXSceneQuickJSDomain *domain, MWXSceneQuickJSOwner **result, uint64_t *template_identity,
    int64_t *layer_id, uint64_t *creator_identity, char *diagnostic, size_t capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic,capacity,"");
    if(!domain || !result || !template_identity || !layer_id || !creator_identity || domain->callback_active)
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    *result=NULL;*template_identity=0;*layer_id=0;*creator_identity=0;
    while(domain->committed_text_clone_head) {
        MWXSceneQuickJSOwner *child=domain->committed_text_clone_head;
        domain->committed_text_clone_head=child->text_clone_next;
        if(!domain->committed_text_clone_head)domain->committed_text_clone_tail=NULL;
        child->text_clone_next=NULL;
        if(!clone_layer_alive(child)) { mwx_scene_quickjs_owner_destroy(child);continue; }
        *result=child;*template_identity=child->text_clone_template_identity;
        *layer_id=child->text_clone_layer_id;*creator_identity=child->text_clone_creator_identity;
        return MWX_SCENE_QUICKJS_OK;
    }
    return MWX_SCENE_QUICKJS_OK;
}

void mwx_scene_quickjs_destroy_text_clone_queue(MWXSceneQuickJSDomain *domain) {
    if(!domain)return;
    MWXSceneQuickJSOwner *child=domain->committed_text_clone_head;
    domain->committed_text_clone_head=domain->committed_text_clone_tail=NULL;
    while(child) { MWXSceneQuickJSOwner *next=child->text_clone_next;child->text_clone_next=NULL;mwx_scene_quickjs_owner_destroy(child);child=next; }
}
