#include "SceneQuickJSInternal.h"

static JSValue active_engine_getter(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv
) {
    (void)this_value;
    (void)argc;
    (void)argv;
    MWXSceneQuickJSDomain *domain = JS_GetContextOpaque(context);
    if (domain == NULL) return JS_UNDEFINED;
    return JS_DupValue(context, domain->active_engine);
}

static MWXSceneQuickJSOwner *current_owner(MWXSceneQuickJSDomain *domain) {
    if (domain == NULL) return NULL;
    return domain->callback_active ? domain->active_owner : domain->module_owner;
}

static JSValue shared_getter(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv
) {
    (void)this_value;
    (void)argc;
    (void)argv;
    MWXSceneQuickJSDomain *domain = JS_GetContextOpaque(context);
    MWXSceneQuickJSOwner *owner = current_owner(domain);
    if (domain == NULL) return JS_UNDEFINED;
    if (owner == NULL || domain->value_only_guard_active || owner->value_only) {
        return JS_ThrowTypeError(
            context, "shared is unavailable outside a stateful SceneScript owner"
        );
    }
    return JS_DupValue(context, domain->shared_value);
}

static JSValue shared_setter(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv
) {
    (void)this_value;
    MWXSceneQuickJSDomain *domain = JS_GetContextOpaque(context);
    MWXSceneQuickJSOwner *owner = current_owner(domain);
    if (domain == NULL || argc != 1) {
        return JS_ThrowTypeError(context, "invalid shared value");
    }
    if (owner == NULL || domain->value_only_guard_active || owner->value_only) {
        return JS_ThrowTypeError(
            context, "shared is unavailable outside a stateful SceneScript owner"
        );
    }
    JSValue next = JS_DupValue(context, argv[0]);
    if (JS_IsException(next)) return next;
    JS_FreeValue(context, domain->shared_value);
    domain->shared_value = next;
    return JS_UNDEFINED;
}

bool mwx_scene_quickjs_install_active_engine_host(
    MWXSceneQuickJSDomain *domain
) {
    JSContext *context = domain->context;
    JSValue getter = JS_NewCFunction(
        context, active_engine_getter, "get engine", 0
    );
    if (JS_IsException(getter)) return false;
    JSValue global = JS_GetGlobalObject(context);
    if (JS_IsException(global)) {
        JS_FreeValue(context, getter);
        return false;
    }
    JSAtom atom = JS_NewAtom(context, "engine");
    if (atom == JS_ATOM_NULL) {
        JS_FreeValue(context, getter);
        JS_FreeValue(context, global);
        return false;
    }
    int result = JS_DefinePropertyGetSet(
        context, global, atom, getter, JS_UNDEFINED, JS_PROP_ENUMERABLE
    );
    JS_FreeAtom(context, atom);
    JS_FreeValue(context, global);
    return result >= 0;
}

bool mwx_scene_quickjs_bind_active_engine(
    MWXSceneQuickJSDomain *domain,
    JSValue engine,
    JSValue *previous_engine
) {
    if (domain == NULL || domain->context == NULL ||
        JS_IsException(engine) || previous_engine == NULL) {
        return false;
    }
    *previous_engine = domain->active_engine;
    domain->active_engine = engine;
    return true;
}

bool mwx_scene_quickjs_restore_active_engine(
    MWXSceneQuickJSDomain *domain,
    JSValue previous_engine
) {
    if (domain == NULL || domain->context == NULL ||
        JS_IsException(previous_engine)) {
        return false;
    }
    JS_FreeValue(domain->context, domain->active_engine);
    domain->active_engine = previous_engine;
    return true;
}

bool mwx_scene_quickjs_install_value_host(MWXSceneQuickJSDomain *domain) {
    static const char source[] =
        "(() => {"
        "class Vec3 {"
        "constructor(x=0,y=x,z=x){if(typeof x==='string'){"
        "const p=x.trim().split(/[\\s,]+/);"
        "if(p.length!==3)throw new TypeError('invalid Vec3 string');"
        "this.x=Number(p[0]);this.y=Number(p[1]);this.z=Number(p[2]);return;}"
        "if(x&&typeof x==='object'){"
        "this.x=Number(x.x);this.y=Number(x.y);"
        "this.z=Number(x.z===undefined?y:x.z);return;}"
        "this.x=Number(x);this.y=Number(y);this.z=Number(z);}"
        "copy(){return new Vec3(this.x,this.y,this.z);}"
        "add(v){if(typeof v==='number'){return new Vec3(this.x+v,this.y+v,this.z+v);}"
        "return new Vec3(this.x+v.x,this.y+v.y,this.z+v.z);}"
        "subtract(v){if(typeof v==='number'){return new Vec3(this.x-v,this.y-v,this.z-v);}"
        "return new Vec3(this.x-v.x,this.y-v.y,this.z-v.z);}"
        "multiply(v){if(typeof v==='number'){return new Vec3(this.x*v,this.y*v,this.z*v);}"
        "return new Vec3(this.x*v.x,this.y*v.y,this.z*v.z);}"
        "divide(v){if(typeof v==='number'){return new Vec3(this.x/v,this.y/v,this.z/v);}"
        "return new Vec3(this.x/v.x,this.y/v.y,this.z/v.z);}"
        "isFinite(){return Number.isFinite(this.x)&&Number.isFinite(this.y)&&Number.isFinite(this.z);}"
        "toString(){return `${this.x} ${this.y} ${this.z}`;}"
        "}"
        "function createScriptProperties(){"
        "const values=Object.create(null);"
        "const add=d=>{if(!d||typeof d.name!=='string'||d.name.length===0)throw new TypeError('invalid script property');values[d.name]=d.value;return builder;};"
        "const builder={addSlider:add,addCheckbox:add,addText:add,addColor:add,addCombo:add,finish:()=>values};"
        "return builder;"
        "}"
        "function assignScriptProperties(target,source){"
        "for(const key of Object.keys(source)){const next=source[key];"
        "target[key]=target[key] instanceof Vec3?new Vec3(next):next;}"
        "return target;}"
        "function deepFreeze(value){if(value&&typeof value==='object'){Object.getOwnPropertyNames(value).forEach(k=>deepFreeze(value[k]));Object.freeze(value);}return value;}"
        "const MediaPlaybackEvent=Object.freeze({PLAYBACK_STOPPED:0,PLAYBACK_PLAYING:1,PLAYBACK_PAUSED:2});"
        "return {Vec3,createScriptProperties,assignScriptProperties,deepFreeze,MediaPlaybackEvent};"
        "})()";
    JSContext *context = domain->context;
    JSValue host = JS_Eval(
        context,
        source,
        sizeof(source) - 1,
        "scene-value-host.js",
        JS_EVAL_TYPE_GLOBAL
    );
    if (JS_IsException(host)) {
        JS_FreeValue(context, host);
        return false;
    }
    JSValue vec3 = JS_GetPropertyStr(context, host, "Vec3");
    JSValue builder = JS_GetPropertyStr(context, host, "createScriptProperties");
    JSValue media_playback = JS_GetPropertyStr(
        context, host, "MediaPlaybackEvent"
    );
    domain->script_property_assigner = JS_GetPropertyStr(
        context, host, "assignScriptProperties"
    );
    domain->deep_freeze = JS_GetPropertyStr(context, host, "deepFreeze");
    JS_FreeValue(context, host);
    if (!JS_IsFunction(context, vec3) || !JS_IsFunction(context, builder) ||
        !JS_IsObject(media_playback) ||
        !JS_IsFunction(context, domain->script_property_assigner) ||
        !JS_IsFunction(context, domain->deep_freeze)) {
        JS_FreeValue(context, vec3);
        JS_FreeValue(context, builder);
        JS_FreeValue(context, media_playback);
        JS_FreeValue(context, domain->script_property_assigner);
        JS_FreeValue(context, domain->deep_freeze);
        domain->script_property_assigner = JS_UNDEFINED;
        domain->deep_freeze = JS_UNDEFINED;
        return false;
    }
    domain->vec3_constructor = JS_DupValue(context, vec3);
    JSValue global = JS_GetGlobalObject(context);
    const int read_only = JS_PROP_ENUMERABLE;
    int vec_result = JS_DefinePropertyValueStr(context, global, "Vec3", vec3, read_only);
    int builder_result = JS_DefinePropertyValueStr(
        context,
        global,
        "createScriptProperties",
        builder,
        read_only
    );
    int media_playback_result = JS_DefinePropertyValueStr(
        context,
        global,
        "MediaPlaybackEvent",
        media_playback,
        read_only
    );
    JSValue shared = JS_NewObject(context);
    JSValue shared_get = JS_NewCFunction(
        context, shared_getter, "get shared", 0
    );
    JSValue shared_set = JS_NewCFunction(
        context, shared_setter, "set shared", 1
    );
    JSAtom shared_atom = JS_NewAtom(context, "shared");
    int shared_result = -1;
    if (!JS_IsException(shared) && !JS_IsException(shared_get) &&
        !JS_IsException(shared_set) && shared_atom != JS_ATOM_NULL) {
        domain->shared_value = shared;
        shared = JS_UNDEFINED;
        shared_result = JS_DefinePropertyGetSet(
            context,
            global,
            shared_atom,
            shared_get,
            shared_set,
            JS_PROP_ENUMERABLE
        );
        shared_get = JS_UNDEFINED;
        shared_set = JS_UNDEFINED;
    }
    JS_FreeAtom(context, shared_atom);
    JS_FreeValue(context, shared);
    JS_FreeValue(context, shared_get);
    JS_FreeValue(context, shared_set);
    JS_FreeValue(context, global);
    return vec_result >= 0 && builder_result >= 0
        && media_playback_result >= 0 && shared_result >= 0;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_update_scalar(
    MWXSceneQuickJSOwner *owner, uint64_t expected_generation, double input,
    const MWXSceneQuickJSFrameInput *frame, double *output,
    char *diagnostic, size_t diagnostic_capacity
) {
    return mwx_scene_quickjs_owner_update_scalar_with_user_properties(
        owner, expected_generation, input, frame, NULL, 0, output,
        diagnostic, diagnostic_capacity
    );
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_update_scalar_with_user_properties(
    MWXSceneQuickJSOwner *owner, uint64_t expected_generation, double input,
    const MWXSceneQuickJSFrameInput *frame,
    const char *user_properties_json, size_t user_properties_length,
    double *output, char *diagnostic, size_t diagnostic_capacity
) {
    return mwx_scene_quickjs_owner_update_scalar_with_properties(
        owner, expected_generation, input, frame, NULL, 0,
        user_properties_json, user_properties_length, output,
        diagnostic, diagnostic_capacity
    );
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_update_scalar_with_properties(
    MWXSceneQuickJSOwner *owner, uint64_t expected_generation, double input,
    const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json, size_t script_properties_length,
    const char *user_properties_json, size_t user_properties_length,
    double *output, char *diagnostic, size_t diagnostic_capacity
) {
    return mwx_scene_quickjs_owner_update_primitive_with_properties(
        owner, expected_generation, input, 0, frame,
        script_properties_json, script_properties_length,
        user_properties_json, user_properties_length, output,
        diagnostic, diagnostic_capacity
    );
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_update_bool_with_properties(
    MWXSceneQuickJSOwner *owner, uint64_t expected_generation, uint32_t input,
    const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json, size_t script_properties_length,
    const char *user_properties_json, size_t user_properties_length,
    uint32_t *output, char *diagnostic, size_t diagnostic_capacity
) {
    if (owner == NULL || !owner->value_only || input > 1 || output == NULL) {
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    double primitive_output = 0;
    MWXSceneQuickJSResult result =
        mwx_scene_quickjs_owner_update_primitive_with_properties(
            owner, expected_generation, input, 1, frame,
            script_properties_json, script_properties_length,
            user_properties_json, user_properties_length, &primitive_output,
            diagnostic, diagnostic_capacity
        );
    if (result == MWX_SCENE_QUICKJS_OK) *output = primitive_output != 0;
    return result;
}
