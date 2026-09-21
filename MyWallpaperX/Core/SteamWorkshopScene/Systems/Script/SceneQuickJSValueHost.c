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

MWXSceneQuickJSResult mwx_scene_quickjs_domain_begin_shared_frame_transaction(
    MWXSceneQuickJSDomain *domain,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    if (diagnostic != NULL && diagnostic_capacity > 0) diagnostic[0] = '\0';
    if (domain == NULL || domain->context == NULL ||
        domain->shared_frame_transaction_active) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "invalid shared frame transaction"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    size_t size = 0;
    uint8_t *snapshot = JS_WriteObject(
        domain->context, &size, domain->shared_value,
        JS_WRITE_OBJ_REFERENCE
    );
    if (snapshot == NULL) {
        return mwx_scene_quickjs_exception_result(
            domain, diagnostic, diagnostic_capacity
        );
    }
    if (size > MWX_SCENE_QUICKJS_MAX_SHARED_SNAPSHOT_BYTES) {
        js_free(domain->context, snapshot);
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "shared frame snapshot byte budget exceeded"
        );
        return MWX_SCENE_QUICKJS_BUDGET_EXCEEDED;
    }
    domain->shared_frame_snapshot = snapshot;
    domain->shared_frame_snapshot_size = size;
    domain->shared_frame_transaction_active = true;
    return MWX_SCENE_QUICKJS_OK;
}

void mwx_scene_quickjs_domain_commit_shared_frame_transaction(
    MWXSceneQuickJSDomain *domain
) {
    if (domain == NULL || domain->context == NULL ||
        !domain->shared_frame_transaction_active) return;
    js_free(domain->context, domain->shared_frame_snapshot);
    domain->shared_frame_snapshot = NULL;
    domain->shared_frame_snapshot_size = 0;
    domain->shared_frame_transaction_active = false;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_discard_shared_frame_transaction(
    MWXSceneQuickJSDomain *domain,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    if (diagnostic != NULL && diagnostic_capacity > 0) diagnostic[0] = '\0';
    if (domain == NULL || domain->context == NULL) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "invalid shared frame rollback"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    if (!domain->shared_frame_transaction_active) {
        return MWX_SCENE_QUICKJS_OK;
    }
    if (domain->shared_frame_snapshot == NULL) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "shared frame rollback snapshot unavailable"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    JSValue restored = JS_ReadObject(
        domain->context,
        domain->shared_frame_snapshot,
        domain->shared_frame_snapshot_size,
        JS_READ_OBJ_REFERENCE
    );
    if (JS_IsException(restored)) {
        return mwx_scene_quickjs_exception_result(
            domain, diagnostic, diagnostic_capacity
        );
    }
    JS_FreeValue(domain->context, domain->shared_value);
    domain->shared_value = restored;
    mwx_scene_quickjs_domain_commit_shared_frame_transaction(domain);
    return MWX_SCENE_QUICKJS_OK;
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
    // Author console output is a compatibility sink. User-requested diagnostics
    // own collection and serialization, so normal launch/frame work stays clean.
    static const char source[] =
        "(() => {"
        "class Vec2 {"
        "constructor(x=0,y=x){if(typeof x==='string'){"
        "const p=x.trim().split(/[\\s,]+/);"
        "if(p.length<2)throw new TypeError('invalid Vec2 string');"
        "this.x=Number(p[0]);this.y=Number(p[1]);return;}"
        "if(x&&typeof x==='object'){this.x=Number(x.x);this.y=Number(x.y);return;}"
        "this.x=Number(x);this.y=Number(y);}"
        "copy(){return new Vec2(this.x,this.y);}"
        "length(){return Math.hypot(this.x,this.y);}"
        "normalize(){const n=this.length();return n===0?new Vec2():this.divide(n);}"
        "add(v){if(typeof v==='number'){return new Vec2(this.x+v,this.y+v);}"
        "return new Vec2(this.x+v.x,this.y+v.y);}"
        "subtract(v){if(typeof v==='number'){return new Vec2(this.x-v,this.y-v);}"
        "return new Vec2(this.x-v.x,this.y-v.y);}"
        "multiply(v){if(typeof v==='number'){return new Vec2(this.x*v,this.y*v);}"
        "return new Vec2(this.x*v.x,this.y*v.y);}"
        "divide(v){if(typeof v==='number'){return new Vec2(this.x/v,this.y/v);}"
        "return new Vec2(this.x/v.x,this.y/v.y);}"
        "mix(v,a){const t=typeof a==='number'?{x:a,y:a}:a;"
        "return new Vec2(this.x+(v.x-this.x)*t.x,this.y+(v.y-this.y)*t.y);}"
        "isFinite(){return Number.isFinite(this.x)&&Number.isFinite(this.y);}"
        "toString(){return `${this.x} ${this.y}`;}"
        "}"
        "class Vec3 {"
        "constructor(x=0,y,z){if(typeof x==='string'){"
        "const p=x.trim().split(/[\\s,]+/);"
        "if(p.length!==3)throw new TypeError('invalid Vec3 string');"
        "this.x=Number(p[0]);this.y=Number(p[1]);this.z=Number(p[2]);return;}"
        "if(x&&typeof x==='object'){"
        "this.x=Number(x.x);this.y=Number(x.y);"
        "this.z=Number(x.z===undefined?(arguments.length>1?y:0):x.z);return;}"
        "if(arguments.length===0){this.x=0;this.y=0;this.z=0;return;}"
        "if(arguments.length===1){this.x=Number(x);this.y=Number(x);this.z=Number(x);return;}"
        "this.x=Number(x);this.y=Number(y);"
        "this.z=Number(arguments.length>2?z:0);}"
        "copy(){return new Vec3(this.x,this.y,this.z);}"
        "length(){return Math.hypot(this.x,this.y,this.z);}"
        "normalize(){const n=this.length();return n===0?new Vec3():this.divide(n);}"
        "add(v){if(typeof v==='number'){return new Vec3(this.x+v,this.y+v,this.z+v);}"
        "return new Vec3(this.x+v.x,this.y+v.y,this.z+v.z);}"
        "subtract(v){if(typeof v==='number'){return new Vec3(this.x-v,this.y-v,this.z-v);}"
        "return new Vec3(this.x-v.x,this.y-v.y,this.z-v.z);}"
        "multiply(v){if(typeof v==='number'){return new Vec3(this.x*v,this.y*v,this.z*v);}"
        "return new Vec3(this.x*v.x,this.y*v.y,this.z*v.z);}"
        "divide(v){if(typeof v==='number'){return new Vec3(this.x/v,this.y/v,this.z/v);}"
        "return new Vec3(this.x/v.x,this.y/v.y,this.z/v.z);}"
        "mix(v,a){const t=typeof a==='number'?{x:a,y:a,z:a}:a;"
        "return new Vec3(this.x+(v.x-this.x)*t.x,this.y+(v.y-this.y)*t.y,this.z+(v.z-this.z)*t.z);}"
        "isFinite(){return Number.isFinite(this.x)&&Number.isFinite(this.y)&&Number.isFinite(this.z);}"
        "toString(){return `${this.x} ${this.y} ${this.z}`;}"
        "}"
        "class Mat4 {"
        "constructor(m){this.m=Array.isArray(m)&&m.length===16?m.slice():[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1];}"
        "static identity(){return new Mat4();}"
        "static fromTranslation(v){const r=new Mat4();r.m[12]=Number(v.x);r.m[13]=Number(v.y);r.m[14]=Number(v.z||0);return r;}"
        "translation(v){if(v===undefined)return new Vec3(this.m[12],this.m[13],this.m[14]);this.m[12]=Number(v.x);this.m[13]=Number(v.y);this.m[14]=Number(v.z||0);return this;}"
        "copy(){return new Mat4(this.m);}"
        "toString(){return this.m.join(' ');}"
        "}"
        "function createScriptProperties(){"
        "const values=Object.create(null);"
        "const add=d=>{if(!d||typeof d.name!=='string'||d.name.length===0)throw new TypeError('invalid script property');values[d.name]=d.value;return builder;};"
        "const builder={addSlider:add,addCheckbox:add,addText:add,addColor:add,addCombo:add,finish:()=>values};"
        "return builder;"
        "}"
        "function assignScriptProperties(target,source){"
        "for(const key of Object.keys(source)){const next=source[key];"
        "target[key]=target[key] instanceof Vec2?new Vec2(next):"
        "target[key] instanceof Vec3?new Vec3(next):next;}"
        "return target;}"
        "function deepFreeze(value){if(value&&typeof value==='object'){Object.getOwnPropertyNames(value).forEach(k=>deepFreeze(value[k]));Object.freeze(value);}return value;}"
        "const console={log(...args){},error(...args){}};"
        "const MediaPlaybackEvent=Object.freeze({PLAYBACK_STOPPED:0,PLAYBACK_PLAYING:1,PLAYBACK_PAUSED:2});"
        "return {Vec2,Vec3,Mat4,createScriptProperties,assignScriptProperties,deepFreeze,console,MediaPlaybackEvent};"
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
    JSValue vec2 = JS_GetPropertyStr(context, host, "Vec2");
    JSValue vec3 = JS_GetPropertyStr(context, host, "Vec3");
    JSValue mat4 = JS_GetPropertyStr(context, host, "Mat4");
    JSValue builder = JS_GetPropertyStr(context, host, "createScriptProperties");
    JSValue media_playback = JS_GetPropertyStr(
        context, host, "MediaPlaybackEvent"
    );
    JSValue console = JS_GetPropertyStr(context, host, "console");
    domain->script_property_assigner = JS_GetPropertyStr(
        context, host, "assignScriptProperties"
    );
    domain->deep_freeze = JS_GetPropertyStr(context, host, "deepFreeze");
    JS_FreeValue(context, host);
    if (!JS_IsFunction(context, vec2) || !JS_IsFunction(context, vec3) ||
        !JS_IsFunction(context, mat4) ||
        !JS_IsFunction(context, builder) ||
        !JS_IsObject(media_playback) || !JS_IsObject(console) ||
        !JS_IsFunction(context, domain->script_property_assigner) ||
        !JS_IsFunction(context, domain->deep_freeze)) {
        JS_FreeValue(context, vec2);
        JS_FreeValue(context, vec3);
        JS_FreeValue(context, mat4);
        JS_FreeValue(context, builder);
        JS_FreeValue(context, media_playback);
        JS_FreeValue(context, console);
        JS_FreeValue(context, domain->script_property_assigner);
        JS_FreeValue(context, domain->deep_freeze);
        domain->script_property_assigner = JS_UNDEFINED;
        domain->deep_freeze = JS_UNDEFINED;
        return false;
    }
    domain->vec2_constructor = JS_DupValue(context, vec2);
    domain->vec3_constructor = JS_DupValue(context, vec3);
    domain->mat4_constructor = JS_DupValue(context, mat4);
    JSValue global = JS_GetGlobalObject(context);
    const int read_only = JS_PROP_ENUMERABLE;
    int vec2_result = JS_DefinePropertyValueStr(
        context, global, "Vec2", vec2, read_only
    );
    int vec3_result = JS_DefinePropertyValueStr(
        context, global, "Vec3", vec3, read_only
    );
    int mat4_result = JS_DefinePropertyValueStr(
        context, global, "Mat4", mat4, read_only
    );
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
    int console_result = JS_DefinePropertyValueStr(
        context,
        global,
        "console",
        console,
        JS_PROP_ENUMERABLE | JS_PROP_WRITABLE
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
    return vec2_result >= 0 && vec3_result >= 0 && mat4_result >= 0 && builder_result >= 0
        && media_playback_result >= 0 && console_result >= 0
        && shared_result >= 0;
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

MWXSceneQuickJSResult mwx_scene_quickjs_owner_update_effectful_bool_with_properties(
    MWXSceneQuickJSOwner *owner, uint64_t expected_generation, uint32_t input,
    const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json, size_t script_properties_length,
    const char *user_properties_json, size_t user_properties_length,
    uint32_t *output, char *diagnostic, size_t diagnostic_capacity
) {
    if (owner == NULL || owner->value_only || !owner->effectful_boolean ||
        input > 1 || output == NULL) {
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
