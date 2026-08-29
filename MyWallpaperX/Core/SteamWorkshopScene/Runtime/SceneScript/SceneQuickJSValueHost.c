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
    int shared_result = JS_SetPropertyStr(
        context, global, "shared", JS_NewObject(context)
    );
    JS_FreeValue(context, global);
    return vec_result >= 0 && builder_result >= 0
        && media_playback_result >= 0 && shared_result >= 0;
}
