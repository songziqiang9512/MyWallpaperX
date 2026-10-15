#include "SceneQuickJSInternal.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

void mwx_scene_quickjs_release_text_source(MWXSceneQuickJSOwner *owner) {
    JSContext *context = owner->domain->context;
    js_free(context, owner->text_template_bytecode);
    JS_FreeValue(context, owner->text_template_source);
    owner->text_template_bytecode = NULL; owner->text_template_bytecode_length = 0;
    owner->text_template_source = JS_UNDEFINED;
}

void mwx_scene_quickjs_capture_text_source(MWXSceneQuickJSOwner *owner, JSValueConst module,
    const char *source, size_t source_length) {
    JSContext *context = owner->domain->context;
    bool had_exception = JS_HasException(context);
    JSValue previous = had_exception ? JS_GetException(context) : JS_UNDEFINED;
    owner->text_template_source = JS_NewStringLen(context, source, source_length);
    if (!JS_IsException(owner->text_template_source))
        owner->text_template_bytecode = JS_WriteObject(context, &owner->text_template_bytecode_length,
            module, JS_WRITE_OBJ_BYTECODE);
    if (JS_HasException(context)) { JSValue error = JS_GetException(context); JS_FreeValue(context, error); }
    if (!owner->text_template_bytecode) mwx_scene_quickjs_release_text_source(owner);
    if (had_exception) JS_Throw(context, previous);
}

// Matching is preparation identity, never source evaluation or JSON coercion.
// These finite traversal bounds also apply to trusted prepared wrappers.
enum { TEXT_MATCH_DEPTH = 32, TEXT_MATCH_NODES = 4096, TEXT_MATCH_KEYS = 1024 };
typedef struct {
    JSContext *context;
    MWXSceneQuickJSDomain *charging_domain;
    JSValue object_prototype, array_prototype;
    JSClassID object_class, array_class;
    JSValueConst candidate_path[TEXT_MATCH_DEPTH];
    JSValueConst prepared_path[TEXT_MATCH_DEPTH];
    size_t remaining;
} TextMatch;

static bool charge(TextMatch *match, uint64_t work) {
    return !match->charging_domain || mwx_scene_quickjs_domain_charge_work(match->charging_domain, work);
}

static bool charge_string(TextMatch *match, JSValueConst value) {
    if (!match->charging_domain || !JS_IsString(value)) return true;
    // A primitive String has an intrinsic own length; no object conversion or
    // author getter is invoked. Charge before its potentially long comparison.
    JSValue length = JS_GetPropertyStr(match->context, value, "length");
    uint32_t units = 0;
    bool valid = !JS_IsException(length) && JS_ToUint32(match->context, &units, length) == 0;
    JS_FreeValue(match->context, length);
    return valid && charge(match, (uint64_t)units + 1);
}

static void free_descriptor(JSContext *context, JSPropertyDescriptor *descriptor) {
    JS_FreeValue(context, descriptor->value);
    JS_FreeValue(context, descriptor->getter);
    JS_FreeValue(context, descriptor->setter);
}

static JSValue own_data_field(JSContext *context, JSValueConst object, const char *key) {
    JSPropertyDescriptor property = {.value=JS_UNDEFINED,.getter=JS_UNDEFINED,.setter=JS_UNDEFINED};
    JSAtom atom = JS_NewAtom(context, key);
    int found = JS_GetOwnProperty(context, &property, object, atom);
    JS_FreeAtom(context, atom);
    JSValue value = JS_UNDEFINED;
    if (found == 1 && (property.flags & JS_PROP_TMASK) == JS_PROP_NORMAL) {
        value = property.value; property.value = JS_UNDEFINED;
    } else if (found < 0) value = JS_EXCEPTION;
    free_descriptor(context, &property);
    return value;
}

static bool plain_data_object(TextMatch *match, JSValueConst value) {
    if (JS_IsProxy(value)) return false;
    JSClassID kind = JS_GetClassID(value);
    if (kind != match->object_class && kind != match->array_class) return false;
    JSValue prototype = JS_GetPrototype(match->context, value);
    bool valid = !JS_IsException(prototype) &&
        ((kind == match->object_class && (JS_IsNull(prototype) ||
          JS_IsSameValue(match->context, prototype, match->object_prototype))) ||
         (kind == match->array_class &&
          JS_IsSameValue(match->context, prototype, match->array_prototype)));
    JS_FreeValue(match->context, prototype);
    return valid;
}

static bool equal_data(TextMatch *match, JSValueConst candidate, JSValueConst prepared, unsigned depth) {
    JSContext *context = match->context;
    if (match->remaining == 0 || !charge(match, 1)) return false;
    --match->remaining;
    if (!JS_IsObject(candidate) || !JS_IsObject(prepared)) {
        if (JS_IsObject(candidate) || JS_IsObject(prepared)) return false;
        if (!(JS_IsNull(candidate) || JS_IsBool(candidate) || JS_IsString(candidate) || JS_IsNumber(candidate)) ||
            !(JS_IsNull(prepared) || JS_IsBool(prepared) || JS_IsString(prepared) || JS_IsNumber(prepared))) return false;
        double number;
        if ((JS_IsNumber(candidate) && (JS_ToFloat64(context, &number, candidate) < 0 || !isfinite(number))) ||
            (JS_IsNumber(prepared) && (JS_ToFloat64(context, &number, prepared) < 0 || !isfinite(number)))) return false;
        return charge_string(match, candidate) && charge_string(match, prepared) && JS_IsSameValue(context, candidate, prepared);
    }
    if (depth >= TEXT_MATCH_DEPTH || !plain_data_object(match, candidate) ||
        !plain_data_object(match, prepared) || JS_IsArray(candidate) != JS_IsArray(prepared)) return false;
    for (unsigned i = 0; i < depth; ++i)
        if (JS_IsSameValue(context, candidate, match->candidate_path[i]) ||
            JS_IsSameValue(context, prepared, match->prepared_path[i])) return false;
    match->candidate_path[depth] = candidate;
    match->prepared_path[depth] = prepared;
    JSPropertyEnum *left = NULL, *right = NULL;
    uint32_t left_count = 0, right_count = 0;
    int flags = JS_GPN_STRING_MASK | JS_GPN_SYMBOL_MASK | JS_GPN_PRIVATE_MASK;
    bool valid = JS_GetOwnPropertyNames(context, &left, &left_count, candidate, flags) == 0 &&
        JS_GetOwnPropertyNames(context, &right, &right_count, prepared, flags) == 0 &&
        left_count == right_count && left_count <= TEXT_MATCH_KEYS;
    // Dense own indices only: an inherited sparse element is not author data.
    if (valid && JS_IsArray(candidate)) {
        JSValue length = JS_GetPropertyStr(context, prepared, "length");
        uint32_t count = 0;
        valid = JS_ToUint32(context, &count, length) == 0 && count <= TEXT_MATCH_KEYS && right_count == count + 1;
        JS_FreeValue(context, length);
    }
    for (uint32_t i = 0; valid && i < right_count; ++i) {
        JSValue key = JS_AtomToValue(context, right[i].atom);
        valid = JS_IsString(key) && charge_string(match, key);
        JS_FreeValue(context, key);
        JSPropertyDescriptor a = {.value=JS_UNDEFINED,.getter=JS_UNDEFINED,.setter=JS_UNDEFINED};
        JSPropertyDescriptor b = {.value=JS_UNDEFINED,.getter=JS_UNDEFINED,.setter=JS_UNDEFINED};
        valid = valid && JS_GetOwnProperty(context, &a, candidate, right[i].atom) == 1 &&
            JS_GetOwnProperty(context, &b, prepared, right[i].atom) == 1 &&
            (a.flags & JS_PROP_TMASK) == JS_PROP_NORMAL && (b.flags & JS_PROP_TMASK) == JS_PROP_NORMAL &&
            equal_data(match, a.value, b.value, depth + 1);
        free_descriptor(context, &a);
        free_descriptor(context, &b);
    }
    JS_FreePropertyEnum(context, left, left_count);
    JS_FreePropertyEnum(context, right, right_count);
    return valid;
}

static TextMatch begin_match(MWXSceneQuickJSDomain *domain, JSContext *context) {
    JSValue object = JS_NewObject(context), array = JS_NewArray(context);
    TextMatch match = {.context=context, .charging_domain=domain,
        .object_prototype=JS_GetPrototype(context, object), .array_prototype=JS_GetPrototype(context, array),
        .object_class=JS_GetClassID(object), .array_class=JS_GetClassID(array), .remaining=TEXT_MATCH_NODES};
    JS_FreeValue(context, object); JS_FreeValue(context, array);
    return match;
}

static void end_match(TextMatch *match) {
    if (JS_HasException(match->context)) {
        JSValue error = JS_GetException(match->context); JS_FreeValue(match->context, error);
    }
    JS_FreeValue(match->context, match->object_prototype);
    JS_FreeValue(match->context, match->array_prototype);
}

static bool wrapper_matches(JSContext *context, JSValueConst candidate, JSValueConst prepared) {
    if (JS_HasException(context)) return false;
    TextMatch match = begin_match(NULL, context);
    bool valid = !JS_HasException(context) && equal_data(&match, candidate, prepared, 0);
    end_match(&match);
    return valid;
}

static MWXSceneQuickJSTextTemplate *template_at(MWXSceneQuickJSDomain *domain, uint64_t identity) {
    if (!domain || identity == 0 || identity > domain->authored_layer_count) return NULL;
    return domain->layers[identity - 1].text_template;
}

static bool same_prepared_semantics(TextMatch *match, const MWXSceneQuickJSTextTemplate *a,
    const MWXSceneQuickJSTextTemplate *b) {
    if (a->kind != b->kind || a->generation != b->generation || a->inputs_available != b->inputs_available ||
        a->bytecode_length != b->bytecode_length || a->alias_count != b->alias_count) return false;
    size_t seed_a = strlen(a->authored_seed), seed_b = strlen(b->authored_seed);
    if (!charge(match, seed_a + seed_b + a->bytecode_length + 1) || seed_a != seed_b ||
        memcmp(a->authored_seed,b->authored_seed,seed_a) ||
        (a->bytecode_length && memcmp(a->bytecode,b->bytecode,a->bytecode_length))) return false;
    if (a->inputs_available && (a->input_length != b->input_length || a->properties_length != b->properties_length ||
        (a->script_properties == NULL) != (b->script_properties == NULL) ||
        !charge(match,a->input_length+a->properties_length+1) ||
        memcmp(a->current_input,b->current_input,a->input_length) ||
        (a->properties_length && memcmp(a->script_properties,b->script_properties,a->properties_length)))) return false;
    for (uint32_t i=0;i<a->alias_count;++i) {
        bool found=false;
        for (uint32_t j=0;j<b->alias_count;++j) {
            size_t key_length=strlen(a->aliases[i].authored_path), value_length=strlen(a->aliases[i].model_path);
            if (!charge(match,key_length+value_length+1)) return false;
            if (!strcmp(a->aliases[i].authored_path,b->aliases[j].authored_path) &&
                !strcmp(a->aliases[i].model_path,b->aliases[j].model_path)) { found=true;break; }
        }
        if (!found) return false;
    }
    return true;
}

uint64_t mwx_scene_quickjs_match_text_template(MWXSceneQuickJSDomain *domain, JSValueConst wrapper) {
    if (!domain || !JS_IsObject(wrapper) || JS_IsProxy(wrapper) || JS_HasException(domain->context)) return 0;
    TextMatch match=begin_match(domain,domain->context);
    uint64_t found=0;
    for (uint32_t i=0;i<domain->authored_layer_count;++i) {
        if (!charge(&match,1) || JS_HasException(domain->context)) { found=0;break; }
        MWXSceneQuickJSTextTemplate *item=domain->layers[i].text_template;
        if (!item || !equal_data(&match,wrapper,item->wrapper,0)) continue;
        if (found && !same_prepared_semantics(&match,domain->layers[found-1].text_template,item)) { found=0;break; }
        if (!found) found=(uint64_t)i+1;
    }
    if (JS_HasException(domain->context) || domain->interrupted || !match.remaining) found=0;
    end_match(&match);
    return found && domain->layers[found-1].text_template->inputs_available ? found : 0;
}

bool mwx_scene_quickjs_text_template_matches_identity(MWXSceneQuickJSDomain *domain, JSValueConst wrapper, uint64_t identity) {
    MWXSceneQuickJSTextTemplate *item=template_at(domain,identity);
    if (!item || !item->inputs_available || JS_HasException(domain->context)) return false;
    TextMatch match=begin_match(domain,domain->context);
    bool valid=!JS_HasException(domain->context) && equal_data(&match,wrapper,item->wrapper,0) && !domain->interrupted;
    end_match(&match);
    return valid;
}

static char *copy_input(JSContext *context, const char *value, size_t length) {
    char *copy = js_malloc(context, length + 1);
    if (copy) { if (length) memcpy(copy, value, length); copy[length] = 0; }
    return copy;
}

static MWXSceneQuickJSResult refresh_inputs(
    MWXSceneQuickJSDomain *domain, uint64_t identity, const char *input, size_t length,
    const char *properties, size_t properties_length, char *diagnostic, size_t capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, capacity, "");
    MWXSceneQuickJSTextTemplate *item = template_at(domain, identity);
    if (!item || domain->callback_active || (input == NULL && length != 0)) return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    item->inputs_available = false;
    if (input == NULL) return MWX_SCENE_QUICKJS_OK;
    if (length > MWX_SCENE_QUICKJS_MAX_LAYER_TEXT || memchr(input, 0, length) ||
        properties_length > MWX_SCENE_QUICKJS_MAX_OWNER_SOURCE_BYTES ||
        (properties == NULL && properties_length != 0) ||
        (properties && memchr(properties, 0, properties_length))) return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    if (item->current_input && item->input_length == length && item->properties_length == properties_length &&
        (item->script_properties == NULL) == (properties == NULL) && !memcmp(item->current_input, input, length) &&
        (!properties_length || !memcmp(item->script_properties, properties, properties_length))) {
        item->inputs_available = true;
        return MWX_SCENE_QUICKJS_OK;
    }
    char *new_input = copy_input(domain->context, input, length);
    char *new_properties = properties ? copy_input(domain->context, properties, properties_length) : NULL;
    if (!new_input || (properties && !new_properties)) {
        js_free(domain->context, new_input); js_free(domain->context, new_properties);
        return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    }
    js_free(domain->context, item->current_input); js_free(domain->context, item->script_properties);
    item->current_input = new_input; item->input_length = length;
    item->script_properties = new_properties; item->properties_length = properties_length;
    item->inputs_available = true;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_refresh_text_template_inputs(
    MWXSceneQuickJSDomain *domain, uint64_t identity, const char *input, size_t length,
    const char *properties, size_t properties_length, char *diagnostic, size_t capacity
) {
    if (!domain || JS_HasException(domain->context)) return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    MWXSceneQuickJSResult result = refresh_inputs(domain, identity, input, length, properties, properties_length, diagnostic, capacity);
    if (result != MWX_SCENE_QUICKJS_OK && JS_HasException(domain->context)) {
        JSValue error = JS_GetException(domain->context); JS_FreeValue(domain->context, error);
    }
    return result;
}

static void destroy_template(JSContext *context, MWXSceneQuickJSTextTemplate *item) {
    if (!item) return;
    JS_FreeValue(context, item->wrapper);
    js_free(context, item->bytecode); js_free(context, item->authored_seed);
    js_free(context, item->current_input); js_free(context, item->script_properties);
    for (uint32_t i = 0; item->aliases && i < item->alias_count; ++i) {
        free(item->aliases[i].authored_path); free(item->aliases[i].model_path);
    }
    free(item->aliases);
    js_free(context, item);
}

bool mwx_scene_quickjs_text_exports_supported(MWXSceneQuickJSOwner *owner) {
    static const char *names[] = {"mediaThumbnailChanged","mediaPlaybackChanged","mediaPropertiesChanged",
        "mediaTimelineChanged","cursorEnter","cursorLeave","cursorDown","cursorMove","cursorUp","cursorClick"};
    if (owner->audio_registration_count || owner->video_ended_callback_count || owner->puppet_animation_configured) return false;
    for (size_t i = 0; i < sizeof(names)/sizeof(names[0]); ++i) {
        uint32_t available = 0;
        if (mwx_scene_quickjs_owner_has_function(owner, names[i], strlen(names[i]), &available, NULL, 0) != MWX_SCENE_QUICKJS_OK || available) return false;
    }
    return true;
}

static MWXSceneQuickJSResult prepare_template(
    MWXSceneQuickJSDomain *domain, MWXSceneQuickJSOwner *source, int64_t layer_id, uint32_t kind,
    const char *seed, size_t seed_length, const char *input, size_t input_length,
    const char *properties, size_t properties_length, uint64_t *identity, char *diagnostic, size_t capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, capacity, "");
    if (identity) *identity = 0;
    if (!domain || domain->callback_active || !identity || !seed || seed_length > MWX_SCENE_QUICKJS_MAX_LAYER_TEXT ||
        memchr(seed, 0, seed_length) || kind < 1 || kind > 3 || JS_HasException(domain->context)) return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    uint32_t index = 0;
    for (; index < domain->authored_layer_count; ++index) if (domain->layers[index].configured && domain->layers[index].layer_id == layer_id) break;
    if (index == domain->authored_layer_count || domain->layers[index].text_template) return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    MWXSceneQuickJSLayerRecord *record = &domain->layers[index];
    if (!record->initial_configuration || (kind == 3 && (!source || source->domain != domain || source->disabled ||
        !source->target_layer_configured || source->target_layer_index != index || !source->text_template_bytecode || !mwx_scene_quickjs_text_exports_supported(source)))) return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    JSContext *context = domain->context;
    JSValue configuration = JS_ReadObject(context, record->initial_configuration, record->initial_configuration_length, 0);
    JSValue wrapper = JS_IsException(configuration) ? JS_UNDEFINED : own_data_field(context, configuration, "text");
    JS_FreeValue(context, configuration);
    if (!JS_IsObject(wrapper) || !wrapper_matches(context, wrapper, wrapper)) { JS_FreeValue(context, wrapper); return MWX_SCENE_QUICKJS_INVALID_ARGUMENT; }
    JSValue script = own_data_field(context, wrapper, "script");
    JSValue user = own_data_field(context, wrapper, "user");
    bool no_user = JS_IsUndefined(user) || JS_IsNull(user);
    bool correct_kind = kind == 3
        ? (JS_IsString(script) && JS_IsSameValue(context, script, source->text_template_source))
        : (JS_IsUndefined(script) && (kind == 1 ? no_user : !no_user));
    JS_FreeValue(context, script); JS_FreeValue(context, user);
    if (!correct_kind) { JS_FreeValue(context, wrapper); return MWX_SCENE_QUICKJS_INVALID_ARGUMENT; }
    MWXSceneQuickJSTextTemplate *item = js_mallocz(context, sizeof(*item));
    if (!item) { JS_FreeValue(context, wrapper); return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED; }
    item->wrapper = wrapper; item->kind = kind;
    item->authored_seed = copy_input(context, seed, seed_length);
    if (!item->authored_seed) { destroy_template(context, item); return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED; }
    if (source) {
        item->generation = source->generation;
        item->alias_count = source->dynamic_image_alias_count;
        item->aliases = calloc(item->alias_count ? item->alias_count : 1, sizeof(*item->aliases));
        if (!item->aliases) { destroy_template(context, item); return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED; }
        for (uint32_t i = 0; i < item->alias_count; ++i) {
            item->aliases[i].authored_path = strdup(source->dynamic_image_aliases[i].authored_path);
            item->aliases[i].model_path = strdup(source->dynamic_image_aliases[i].model_path);
            if (!item->aliases[i].authored_path || !item->aliases[i].model_path) { destroy_template(context, item); return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED; }
        }
    }
    record->text_template = item;
    MWXSceneQuickJSResult result = mwx_scene_quickjs_domain_refresh_text_template_inputs(domain, (uint64_t)index + 1, input, input_length, properties, properties_length, diagnostic, capacity);
    if (result != MWX_SCENE_QUICKJS_OK) { record->text_template = NULL; destroy_template(context, item); return result; }
    if (kind == 3) {
        item->bytecode = source->text_template_bytecode;
        item->bytecode_length = source->text_template_bytecode_length;
        source->text_template_bytecode = NULL; source->text_template_bytecode_length = 0;
        mwx_scene_quickjs_release_text_source(source);
    }
    *identity = (uint64_t)index + 1;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_prepare_text_template(
    MWXSceneQuickJSDomain *domain, MWXSceneQuickJSOwner *source, int64_t layer_id, uint32_t kind,
    const char *seed, size_t seed_length, const char *input, size_t input_length,
    const char *properties, size_t properties_length, uint64_t *identity, char *diagnostic, size_t capacity
) {
    if (!domain || JS_HasException(domain->context)) return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    MWXSceneQuickJSResult result = prepare_template(domain, source, layer_id, kind, seed, seed_length,
        input, input_length, properties, properties_length, identity, diagnostic, capacity);
    if (result != MWX_SCENE_QUICKJS_OK && JS_HasException(domain->context)) {
        JSValue error = JS_GetException(domain->context); JS_FreeValue(domain->context, error);
    }
    return result;
}

char *mwx_scene_quickjs_text_template_input(MWXSceneQuickJSDomain *domain, uint64_t identity) {
    MWXSceneQuickJSTextTemplate *item = template_at(domain, identity);
    return item && item->inputs_available &&
        mwx_scene_quickjs_domain_charge_work(domain, item->input_length + 1) ? strdup(item->current_input) : NULL;
}

void mwx_scene_quickjs_destroy_text_templates(MWXSceneQuickJSDomain *domain) {
    if (!domain || !domain->context) return;
    for (uint32_t i = 0; i < domain->authored_layer_count; ++i) {
        destroy_template(domain->context, domain->layers[i].text_template);
        domain->layers[i].text_template = NULL;
    }
}
