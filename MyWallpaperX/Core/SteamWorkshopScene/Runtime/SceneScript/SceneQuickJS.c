#include "SceneQuickJS.h"

#include "QuickJSNG/quickjs.h"

#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MWX_SCENE_QUICKJS_MAX_MATERIAL_FUNCTION_MUTATIONS 16
#define MWX_SCENE_QUICKJS_MAX_MATERIAL_FUNCTION_NAME 128
#define MWX_SCENE_QUICKJS_MAX_EFFECTS 1024
#define MWX_SCENE_QUICKJS_MAX_EFFECT_NAME 256

typedef struct MWXSceneQuickJSMaterialFunctionMutationRecord {
    uint32_t effect_index;
    char function_name[MWX_SCENE_QUICKJS_MAX_MATERIAL_FUNCTION_NAME];
} MWXSceneQuickJSMaterialFunctionMutationRecord;

struct MWXSceneQuickJSDomain {
    JSRuntime *runtime;
    JSContext *context;
    JSValue deep_freeze;
    uint64_t interrupt_budget;
    bool interrupted;
};

struct MWXSceneQuickJSOwner {
    MWXSceneQuickJSDomain *domain;
    JSValue module;
    uint64_t generation;
    bool initialized;
    bool disabled;
    JSValue material_function_layer;
    size_t material_function_count;
    bool material_function_overflow;
    uint32_t effect_count;
    char **effect_names;
    MWXSceneQuickJSMaterialFunctionMutationRecord material_functions[
        MWX_SCENE_QUICKJS_MAX_MATERIAL_FUNCTION_MUTATIONS
    ];
};

typedef struct MWXSceneQuickJSEffectHandle {
    MWXSceneQuickJSOwner *owner;
    uint32_t effect_index;
} MWXSceneQuickJSEffectHandle;

static JSValue wemath_smooth_step(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv
) {
    (void)this_value;
    if (argc != 3) {
        return JS_ThrowTypeError(context, "WEMath.smoothStep expects three numbers");
    }
    double minimum = 0;
    double maximum = 0;
    double value = 0;
    if (JS_ToFloat64(context, &minimum, argv[0]) < 0 ||
        JS_ToFloat64(context, &maximum, argv[1]) < 0 ||
        JS_ToFloat64(context, &value, argv[2]) < 0 ||
        !isfinite(minimum) || !isfinite(maximum) || !isfinite(value) ||
        minimum == maximum) {
        return JS_ThrowTypeError(context, "WEMath.smoothStep arguments are invalid");
    }
    double normalized = (value - minimum) / (maximum - minimum);
    normalized = fmin(fmax(normalized, 0), 1);
    return JS_NewFloat64(
        context,
        normalized * normalized * (3 - 2 * normalized)
    );
}

static int initialize_wemath_module(JSContext *context, JSModuleDef *module) {
    JSValue smooth_step = JS_NewCFunction(
        context,
        wemath_smooth_step,
        "smoothStep",
        3
    );
    if (JS_IsException(smooth_step)) {
        return -1;
    }
    return JS_SetModuleExport(context, module, "smoothStep", smooth_step);
}

static bool install_value_host(MWXSceneQuickJSDomain *domain) {
    static const char source[] =
        "(() => {"
        "class Vec3 {"
        "constructor(x=0,y=x,z=x){this.x=Number(x);this.y=Number(y);this.z=Number(z);}"
        "copy(){return new Vec3(this.x,this.y,this.z);}"
        "add(v){if(typeof v==='number'){return new Vec3(this.x+v,this.y+v,this.z+v);}"
        "return new Vec3(this.x+v.x,this.y+v.y,this.z+v.z);}"
        "multiply(v){if(typeof v==='number'){return new Vec3(this.x*v,this.y*v,this.z*v);}"
        "return new Vec3(this.x*v.x,this.y*v.y,this.z*v.z);}"
        "isFinite(){return Number.isFinite(this.x)&&Number.isFinite(this.y)&&Number.isFinite(this.z);}"
        "}"
        "function createScriptProperties(){"
        "const values=Object.create(null);"
        "const add=d=>{if(!d||typeof d.name!=='string'||d.name.length===0)throw new TypeError('invalid script property');values[d.name]=d.value;return builder;};"
        "const builder={addSlider:add,addCheckbox:add,addText:add,addColor:add,addCombo:add,finish:()=>values};"
        "return builder;"
        "}"
        "function deepFreeze(value){if(value&&typeof value==='object'){Object.getOwnPropertyNames(value).forEach(k=>deepFreeze(value[k]));Object.freeze(value);}return value;}"
        "return {Vec3,createScriptProperties,deepFreeze};"
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
    domain->deep_freeze = JS_GetPropertyStr(context, host, "deepFreeze");
    JS_FreeValue(context, host);
    if (!JS_IsFunction(context, vec3) || !JS_IsFunction(context, builder) ||
        !JS_IsFunction(context, domain->deep_freeze)) {
        JS_FreeValue(context, vec3);
        JS_FreeValue(context, builder);
        JS_FreeValue(context, domain->deep_freeze);
        domain->deep_freeze = JS_UNDEFINED;
        return false;
    }
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
    JS_FreeValue(context, global);
    return vec_result >= 0 && builder_result >= 0;
}

static JSModuleDef *load_allowlisted_module(
    JSContext *context,
    const char *module_name,
    void *opaque
) {
    (void)opaque;
    if (module_name == NULL || strcmp(module_name, "WEMath") != 0) {
        JS_ThrowReferenceError(
            context,
            "SceneScript module is not allowlisted: %s",
            module_name != NULL ? module_name : "<null>"
        );
        return NULL;
    }
    JSModuleDef *module = JS_NewCModule(
        context,
        module_name,
        initialize_wemath_module
    );
    if (module == NULL || JS_AddModuleExport(context, module, "smoothStep") < 0) {
        return NULL;
    }
    return module;
}

static void clear_diagnostic(char *diagnostic, size_t capacity) {
    if (diagnostic != NULL && capacity > 0) {
        diagnostic[0] = '\0';
    }
}

static void write_diagnostic(
    char *diagnostic,
    size_t capacity,
    const char *message
) {
    if (diagnostic == NULL || capacity == 0) {
        return;
    }
    snprintf(diagnostic, capacity, "%s", message != NULL ? message : "");
}

static void write_exception(
    MWXSceneQuickJSDomain *domain,
    char *diagnostic,
    size_t capacity
) {
    JSValue exception = JS_GetException(domain->context);
    const char *message = JS_ToCString(domain->context, exception);
    write_diagnostic(diagnostic, capacity, message != NULL ? message : "script exception");
    if (message != NULL) {
        JS_FreeCString(domain->context, message);
    }
    JS_FreeValue(domain->context, exception);
}

static void write_value_diagnostic(
    MWXSceneQuickJSDomain *domain,
    JSValueConst value,
    char *diagnostic,
    size_t capacity,
    const char *fallback
) {
    const char *message = JS_ToCString(domain->context, value);
    write_diagnostic(diagnostic, capacity, message != NULL ? message : fallback);
    if (message != NULL) {
        JS_FreeCString(domain->context, message);
    }
}

static JSValue execute_material_function(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv,
    int magic,
    void *opaque
) {
    (void)this_value;
    (void)magic;
    MWXSceneQuickJSEffectHandle *handle = (MWXSceneQuickJSEffectHandle *)opaque;
    if (handle == NULL || handle->owner == NULL || argc != 1 ||
        !JS_IsString(argv[0])) {
        return JS_ThrowTypeError(context, "executeMaterialFunction expects one string");
    }
    MWXSceneQuickJSOwner *owner = handle->owner;
    if (owner->material_function_count >=
        MWX_SCENE_QUICKJS_MAX_MATERIAL_FUNCTION_MUTATIONS) {
        owner->material_function_overflow = true;
        return JS_ThrowInternalError(context, "material function mutation buffer exceeded");
    }
    size_t length = 0;
    const char *name = JS_ToCStringLen(context, &length, argv[0]);
    if (name == NULL || length == 0 || length >= MWX_SCENE_QUICKJS_MAX_MATERIAL_FUNCTION_NAME) {
        if (name != NULL) {
            JS_FreeCString(context, name);
        }
        return JS_ThrowTypeError(context, "material function name is invalid");
    }
    MWXSceneQuickJSMaterialFunctionMutationRecord *record =
        &owner->material_functions[owner->material_function_count];
    record->effect_index = handle->effect_index;
    memcpy(record->function_name, name, length);
    record->function_name[length] = '\0';
    owner->material_function_count += 1;
    JS_FreeCString(context, name);
    return JS_UNDEFINED;
}

static void free_effect_handle(void *opaque) {
    free(opaque);
}

static JSValue get_effect(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv,
    int magic,
    void *opaque
) {
    (void)this_value;
    (void)magic;
    MWXSceneQuickJSOwner *owner = (MWXSceneQuickJSOwner *)opaque;
    if (owner == NULL || argc != 1 || owner->effect_names == NULL) {
        return JS_ThrowTypeError(context, "getEffect host is unavailable");
    }
    int64_t index = -1;
    if (JS_IsString(argv[0])) {
        const char *name = JS_ToCString(context, argv[0]);
        if (name == NULL) {
            return JS_EXCEPTION;
        }
        for (uint32_t candidate = 0; candidate < owner->effect_count; ++candidate) {
            if (owner->effect_names[candidate] != NULL &&
                strcmp(owner->effect_names[candidate], name) == 0) {
                index = candidate;
                break;
            }
        }
        JS_FreeCString(context, name);
    } else if (JS_IsNumber(argv[0])) {
        double numeric_index = -1;
        if (JS_ToFloat64(context, &numeric_index, argv[0]) < 0 ||
            !isfinite(numeric_index) || floor(numeric_index) != numeric_index ||
            numeric_index < 0 || numeric_index > UINT32_MAX) {
            return JS_ThrowRangeError(context, "getEffect index is invalid");
        }
        index = (int64_t)numeric_index;
    } else {
        return JS_ThrowTypeError(context, "getEffect expects one name or index");
    }
    if (index < 0 || index >= owner->effect_count) {
        return JS_ThrowRangeError(context, "getEffect target does not exist");
    }
    JSValue effect = JS_NewObject(context);
    if (JS_IsException(effect)) {
        return effect;
    }
    MWXSceneQuickJSEffectHandle *handle = calloc(1, sizeof(*handle));
    if (handle == NULL) {
        JS_FreeValue(context, effect);
        return JS_ThrowInternalError(context, "material effect handle allocation failed");
    }
    handle->owner = owner;
    handle->effect_index = (uint32_t)index;
    JSValue callback = JS_NewCClosure(
        context,
        execute_material_function,
        "executeMaterialFunction",
        free_effect_handle,
        1,
        0,
        handle
    );
    if (JS_IsException(callback) ||
        JS_DefinePropertyValueStr(
            context,
            effect,
            "executeMaterialFunction",
            callback,
            JS_PROP_ENUMERABLE
        ) < 0) {
        JS_FreeValue(context, effect);
        return JS_EXCEPTION;
    }
    const char *effect_name = owner->effect_names[index];
    if (effect_name != NULL &&
        JS_DefinePropertyValueStr(
            context,
            effect,
            "name",
            JS_NewString(context, effect_name),
            JS_PROP_ENUMERABLE
        ) < 0) {
        JS_FreeValue(context, effect);
        return JS_EXCEPTION;
    }
    return effect;
}

static JSValue get_effect_count(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv,
    int magic,
    void *opaque
) {
    (void)this_value;
    (void)argc;
    (void)argv;
    (void)magic;
    MWXSceneQuickJSOwner *owner = (MWXSceneQuickJSOwner *)opaque;
    if (owner == NULL || owner->effect_names == NULL) {
        return JS_ThrowTypeError(context, "getEffectCount host is unavailable");
    }
    return JS_NewUint32(context, owner->effect_count);
}

static bool install_material_function_host(MWXSceneQuickJSOwner *owner) {
    JSContext *context = owner->domain->context;
    JSValue layer = JS_NewObject(context);
    if (JS_IsException(layer)) {
        return false;
    }
    JSValue getter = JS_NewCClosure(
        context,
        get_effect,
        "getEffect",
        NULL,
        1,
        0,
        owner
    );
    JSValue count = JS_NewCClosure(
        context,
        get_effect_count,
        "getEffectCount",
        NULL,
        0,
        0,
        owner
    );
    if (JS_IsException(getter) || JS_IsException(count) ||
        JS_DefinePropertyValueStr(
            context, layer, "getEffect", getter, JS_PROP_ENUMERABLE
        ) < 0 ||
        JS_DefinePropertyValueStr(
            context, layer, "getEffectCount", count, JS_PROP_ENUMERABLE
        ) < 0) {
        JS_FreeValue(context, layer);
        return false;
    }
    owner->material_function_layer = JS_DupValue(context, layer);
    JS_FreeValue(context, layer);
    return true;
}

static bool bind_material_function_host(
    MWXSceneQuickJSOwner *owner,
    JSValue *previous_global_layer
) {
    if (owner == NULL || previous_global_layer == NULL ||
        JS_IsUndefined(owner->material_function_layer)) {
        return false;
    }
    JSContext *context = owner->domain->context;
    JSValue global = JS_GetGlobalObject(context);
    JSValue previous = JS_GetPropertyStr(context, global, "thisLayer");
    if (JS_IsException(previous)) {
        JS_FreeValue(context, global);
        return false;
    }
    JSValue layer = JS_DupValue(context, owner->material_function_layer);
    if (JS_SetPropertyStr(context, global, "thisLayer", layer) < 0) {
        JS_FreeValue(context, previous);
        JS_FreeValue(context, global);
        return false;
    }
    *previous_global_layer = previous;
    JS_FreeValue(context, global);
    return true;
}

static bool restore_material_function_host(
    MWXSceneQuickJSOwner *owner,
    JSValue previous_global_layer
) {
    if (owner == NULL) {
        return false;
    }
    JSContext *context = owner->domain->context;
    JSValue global = JS_GetGlobalObject(context);
    int result = JS_SetPropertyStr(
        context,
        global,
        "thisLayer",
        previous_global_layer
    );
    JS_FreeValue(context, global);
    return result >= 0;
}

static bool bind_frame_engine_host(
    MWXSceneQuickJSOwner *owner,
    const MWXSceneQuickJSFrameInput *frame,
    const char *user_properties_json,
    size_t user_properties_length,
    JSValue *previous_global_engine
) {
    if (owner == NULL || frame == NULL || previous_global_engine == NULL) {
        return false;
    }
    JSContext *context = owner->domain->context;
    JSValue engine = JS_NewObject(context);
    if (JS_IsException(engine)) {
        return false;
    }
    const int read_only = JS_PROP_ENUMERABLE;
    JSValue user_properties = JS_NewObject(context);
    if (user_properties_json != NULL && user_properties_length > 0) {
        JS_FreeValue(context, user_properties);
        user_properties = JS_ParseJSON(
            context,
            user_properties_json,
            user_properties_length,
            "engine.userProperties"
        );
        if (JS_IsException(user_properties) || !JS_IsObject(user_properties)) {
            JS_FreeValue(context, user_properties);
            JS_FreeValue(context, engine);
            return false;
        }
    }
    JSValue freeze_argument = JS_DupValue(context, user_properties);
    JSValue frozen = JS_Call(
        context,
        owner->domain->deep_freeze,
        JS_UNDEFINED,
        1,
        &freeze_argument
    );
    JS_FreeValue(context, freeze_argument);
    if (JS_IsException(frozen)) {
        JS_FreeValue(context, frozen);
        JS_FreeValue(context, user_properties);
        JS_FreeValue(context, engine);
        return false;
    }
    JS_FreeValue(context, frozen);
    if (JS_DefinePropertyValueStr(
            context,
            engine,
            "timeOfDay",
            JS_NewFloat64(context, frame->time_of_day),
            read_only
        ) < 0 ||
        JS_DefinePropertyValueStr(
            context,
            engine,
            "frametime",
            JS_NewFloat64(context, frame->frame_time),
            read_only
        ) < 0 ||
        JS_DefinePropertyValueStr(
            context,
            engine,
            "runtime",
            JS_NewFloat64(context, frame->runtime),
            read_only
        ) < 0 ||
        JS_DefinePropertyValueStr(
            context,
            engine,
            "userProperties",
            user_properties,
            read_only
        ) < 0) {
        JS_FreeValue(context, engine);
        return false;
    }
    JSValue global = JS_GetGlobalObject(context);
    JSValue previous = JS_GetPropertyStr(context, global, "engine");
    if (JS_IsException(previous)) {
        JS_FreeValue(context, engine);
        JS_FreeValue(context, global);
        return false;
    }
    if (JS_SetPropertyStr(context, global, "engine", engine) < 0) {
        JS_FreeValue(context, previous);
        JS_FreeValue(context, global);
        return false;
    }
    *previous_global_engine = previous;
    JS_FreeValue(context, global);
    return true;
}

static bool restore_frame_engine_host(
    MWXSceneQuickJSOwner *owner,
    JSValue previous_global_engine
) {
    if (owner == NULL) {
        return false;
    }
    JSContext *context = owner->domain->context;
    JSValue global = JS_GetGlobalObject(context);
    int result = JS_SetPropertyStr(
        context,
        global,
        "engine",
        previous_global_engine
    );
    JS_FreeValue(context, global);
    return result >= 0;
}

static int interrupt_handler(JSRuntime *runtime, void *opaque) {
    (void)runtime;
    MWXSceneQuickJSDomain *domain = (MWXSceneQuickJSDomain *)opaque;
    if (domain == NULL || domain->interrupt_budget == 0) {
        if (domain != NULL) {
            domain->interrupted = true;
        }
        return 1;
    }
    domain->interrupt_budget -= 1;
    return 0;
}

static MWXSceneQuickJSResult exception_result(
    MWXSceneQuickJSDomain *domain,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    write_exception(domain, diagnostic, diagnostic_capacity);
    if (domain->interrupted) {
        return MWX_SCENE_QUICKJS_BUDGET_EXCEEDED;
    }
    if (diagnostic != NULL && strstr(diagnostic, "out of memory") != NULL) {
        return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    }
    return MWX_SCENE_QUICKJS_EXCEPTION;
}

static bool get_function(
    MWXSceneQuickJSOwner *owner,
    const char *name,
    JSValue *function,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    MWXSceneQuickJSDomain *domain = owner->domain;
    *function = JS_GetPropertyStr(domain->context, owner->module, name);
    if (JS_IsException(*function)) {
        write_exception(domain, diagnostic, diagnostic_capacity);
        return false;
    }
    if (!JS_IsFunction(domain->context, *function)) {
        JS_FreeValue(domain->context, *function);
        *function = JS_UNDEFINED;
    }
    return true;
}

static MWXSceneQuickJSResult call_scalar(
    MWXSceneQuickJSOwner *owner,
    JSValueConst function,
    double input,
    const MWXSceneQuickJSFrameInput *frame,
    const char *user_properties_json,
    size_t user_properties_length,
    double *output,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    MWXSceneQuickJSDomain *domain = owner->domain;
    JSValue previous_global_layer = JS_UNDEFINED;
    if (!bind_material_function_host(owner, &previous_global_layer)) {
        write_diagnostic(
            diagnostic,
            diagnostic_capacity,
            "SceneScript material function host unavailable"
        );
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    JSValue previous_global_engine = JS_UNDEFINED;
    if (!bind_frame_engine_host(
            owner,
            frame,
            user_properties_json,
            user_properties_length,
            &previous_global_engine
        )) {
        restore_material_function_host(owner, previous_global_layer);
        write_diagnostic(
            diagnostic,
            diagnostic_capacity,
            "SceneScript frame engine host unavailable"
        );
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    JSValue argument = JS_NewFloat64(domain->context, input);
    JSValue result = JS_Call(
        domain->context,
        function,
        owner->module,
        1,
        &argument
    );
    JS_FreeValue(domain->context, argument);
    const bool engine_restored = restore_frame_engine_host(
        owner,
        previous_global_engine
    );
    const bool layer_restored = restore_material_function_host(
        owner,
        previous_global_layer
    );
    const bool restored = engine_restored && layer_restored;
    if (!restored) {
        JS_FreeValue(domain->context, result);
        write_diagnostic(
            diagnostic,
            diagnostic_capacity,
            "SceneScript material function host restore failed"
        );
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    if (JS_IsException(result)) {
        MWXSceneQuickJSResult failure = exception_result(
            domain, diagnostic, diagnostic_capacity
        );
        JS_FreeValue(domain->context, result);
        if (owner->material_function_overflow) {
            write_diagnostic(
                diagnostic,
                diagnostic_capacity,
                "material function mutation buffer exceeded"
            );
            return MWX_SCENE_QUICKJS_MUTATION_OVERFLOW;
        }
        return failure;
    }
    if (JS_IsUndefined(result)) {
        *output = input;
        JS_FreeValue(domain->context, result);
        return MWX_SCENE_QUICKJS_OK;
    }
    double value = 0;
    int conversion = JS_ToFloat64(domain->context, &value, result);
    JS_FreeValue(domain->context, result);
    if (conversion < 0 || !isfinite(value)) {
        write_diagnostic(
            diagnostic,
            diagnostic_capacity,
            "callback returned non-finite or non-scalar value"
        );
        return MWX_SCENE_QUICKJS_BAD_RETURN;
    }
    *output = value;
    return MWX_SCENE_QUICKJS_OK;
}

static bool assign_script_properties(
    MWXSceneQuickJSOwner *owner,
    const char *json,
    size_t length
) {
    if (json == NULL || length == 0) {
        return true;
    }
    JSContext *context = owner->domain->context;
    JSValue target = JS_GetPropertyStr(context, owner->module, "scriptProperties");
    JSValue source = JS_ParseJSON(context, json, length, "scriptProperties");
    if (JS_IsException(target) || JS_IsException(source) ||
        !JS_IsObject(target) || !JS_IsObject(source)) {
        JS_FreeValue(context, target);
        JS_FreeValue(context, source);
        return false;
    }
    JSValue global = JS_GetGlobalObject(context);
    JSValue object = JS_GetPropertyStr(context, global, "Object");
    JSValue assign = JS_GetPropertyStr(context, object, "assign");
    JSValue arguments[2] = {
        JS_DupValue(context, target),
        JS_DupValue(context, source),
    };
    JSValue result = JS_Call(context, assign, object, 2, arguments);
    JS_FreeValue(context, arguments[0]);
    JS_FreeValue(context, arguments[1]);
    JS_FreeValue(context, assign);
    JS_FreeValue(context, object);
    JS_FreeValue(context, global);
    JS_FreeValue(context, target);
    JS_FreeValue(context, source);
    const bool success = !JS_IsException(result);
    JS_FreeValue(context, result);
    return success;
}

static bool read_vec3(JSContext *context, JSValueConst value, double output[3]) {
    if (!JS_IsObject(value)) {
        double scalar = 0;
        if (JS_ToFloat64(context, &scalar, value) < 0 || !isfinite(scalar)) {
            return false;
        }
        output[0] = scalar;
        output[1] = scalar;
        output[2] = scalar;
        return true;
    }
    static const char *names[] = {"x", "y", "z"};
    for (size_t index = 0; index < 3; index += 1) {
        JSValue component = JS_GetPropertyStr(context, value, names[index]);
        int conversion = JS_ToFloat64(context, &output[index], component);
        JS_FreeValue(context, component);
        if (conversion < 0 || !isfinite(output[index])) {
            return false;
        }
    }
    return true;
}

static MWXSceneQuickJSResult call_vec3(
    MWXSceneQuickJSOwner *owner,
    JSValueConst function,
    const double input[3],
    const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json,
    size_t script_properties_length,
    const char *user_properties_json,
    size_t user_properties_length,
    double output[3],
    char *diagnostic,
    size_t diagnostic_capacity
) {
    MWXSceneQuickJSDomain *domain = owner->domain;
    if (!assign_script_properties(owner, script_properties_json, script_properties_length)) {
        write_diagnostic(diagnostic, diagnostic_capacity, "SceneScript properties unavailable");
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    JSValue previous_global_layer = JS_UNDEFINED;
    if (!bind_material_function_host(owner, &previous_global_layer)) {
        write_diagnostic(diagnostic, diagnostic_capacity, "SceneScript material function host unavailable");
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    JSValue previous_global_engine = JS_UNDEFINED;
    if (!bind_frame_engine_host(
            owner,
            frame,
            user_properties_json,
            user_properties_length,
            &previous_global_engine
        )) {
        restore_material_function_host(owner, previous_global_layer);
        write_diagnostic(diagnostic, diagnostic_capacity, "SceneScript frame engine host unavailable");
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    JSValue argument = JS_NewObject(domain->context);
    JS_SetPropertyStr(domain->context, argument, "x", JS_NewFloat64(domain->context, input[0]));
    JS_SetPropertyStr(domain->context, argument, "y", JS_NewFloat64(domain->context, input[1]));
    JS_SetPropertyStr(domain->context, argument, "z", JS_NewFloat64(domain->context, input[2]));
    JSValue callback_argument = JS_DupValue(domain->context, argument);
    JSValue result = JS_Call(domain->context, function, owner->module, 1, &callback_argument);
    JS_FreeValue(domain->context, callback_argument);
    const bool engine_restored = restore_frame_engine_host(owner, previous_global_engine);
    const bool layer_restored = restore_material_function_host(owner, previous_global_layer);
    if (!engine_restored || !layer_restored) {
        JS_FreeValue(domain->context, argument);
        JS_FreeValue(domain->context, result);
        write_diagnostic(diagnostic, diagnostic_capacity, "SceneScript host restore failed");
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    if (JS_IsException(result)) {
        JS_FreeValue(domain->context, argument);
        MWXSceneQuickJSResult failure = exception_result(domain, diagnostic, diagnostic_capacity);
        JS_FreeValue(domain->context, result);
        return owner->material_function_overflow
            ? MWX_SCENE_QUICKJS_MUTATION_OVERFLOW : failure;
    }
    JSValueConst value = JS_IsUndefined(result) ? argument : result;
    const bool valid = read_vec3(domain->context, value, output);
    JS_FreeValue(domain->context, argument);
    JS_FreeValue(domain->context, result);
    if (!valid) {
        write_diagnostic(diagnostic, diagnostic_capacity, "callback returned invalid Vec3 value");
        return MWX_SCENE_QUICKJS_BAD_RETURN;
    }
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSDomain *mwx_scene_quickjs_domain_create(
    size_t heap_limit,
    size_t stack_limit,
    uint64_t interrupt_budget,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    clear_diagnostic(diagnostic, diagnostic_capacity);
    if (heap_limit == 0 || stack_limit == 0 || interrupt_budget == 0) {
        write_diagnostic(diagnostic, diagnostic_capacity, "invalid SceneScript domain configuration");
        return NULL;
    }
    MWXSceneQuickJSDomain *domain = calloc(1, sizeof(*domain));
    if (domain == NULL) {
        write_diagnostic(diagnostic, diagnostic_capacity, "SceneScript domain allocation failed");
        return NULL;
    }
    domain->runtime = JS_NewRuntime();
    if (domain->runtime == NULL) {
        free(domain);
        write_diagnostic(diagnostic, diagnostic_capacity, "QuickJS runtime allocation failed");
        return NULL;
    }
    domain->interrupt_budget = interrupt_budget;
    JS_SetMemoryLimit(domain->runtime, heap_limit);
    JS_SetMaxStackSize(domain->runtime, stack_limit);
    JS_SetInterruptHandler(domain->runtime, interrupt_handler, domain);
    JS_SetModuleLoaderFunc(
        domain->runtime,
        NULL,
        load_allowlisted_module,
        domain
    );
    domain->context = JS_NewContext(domain->runtime);
    if (domain->context == NULL) {
        JS_FreeRuntime(domain->runtime);
        free(domain);
        write_diagnostic(diagnostic, diagnostic_capacity, "QuickJS context allocation failed");
        return NULL;
    }
    domain->deep_freeze = JS_UNDEFINED;
    if (!install_value_host(domain)) {
        JS_FreeContext(domain->context);
        JS_FreeRuntime(domain->runtime);
        free(domain);
        write_diagnostic(diagnostic, diagnostic_capacity, "SceneScript value host unavailable");
        return NULL;
    }
    return domain;
}

void mwx_scene_quickjs_domain_destroy(MWXSceneQuickJSDomain *domain) {
    if (domain == NULL) {
        return;
    }
    if (domain->context != NULL) {
        JS_FreeValue(domain->context, domain->deep_freeze);
        JS_FreeContext(domain->context);
    }
    if (domain->runtime != NULL) {
        JS_FreeRuntime(domain->runtime);
    }
    free(domain);
}

void mwx_scene_quickjs_domain_reset_budget(
    MWXSceneQuickJSDomain *domain,
    uint64_t interrupt_budget
) {
    if (domain == NULL) {
        return;
    }
    domain->interrupt_budget = interrupt_budget;
    domain->interrupted = false;
}

MWXSceneQuickJSOwner *mwx_scene_quickjs_owner_create(
    MWXSceneQuickJSDomain *domain,
    const char *source,
    size_t source_length,
    uint64_t generation,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    clear_diagnostic(diagnostic, diagnostic_capacity);
    if (domain == NULL || source == NULL || source_length == 0 || generation == 0) {
        write_diagnostic(diagnostic, diagnostic_capacity, "invalid SceneScript owner configuration");
        return NULL;
    }
    char *module_source = malloc(source_length + 1);
    if (module_source == NULL) {
        write_diagnostic(diagnostic, diagnostic_capacity, "SceneScript source allocation failed");
        return NULL;
    }
    memcpy(module_source, source, source_length);
    module_source[source_length] = '\0';
    domain->interrupted = false;
    JSValue module = JS_Eval(
        domain->context,
        module_source,
        source_length,
        "inline.scene.js",
        JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY
    );
    free(module_source);
    if (JS_IsException(module)) {
        write_exception(domain, diagnostic, diagnostic_capacity);
        JS_FreeValue(domain->context, module);
        return NULL;
    }

    JSModuleDef *module_definition = JS_VALUE_GET_PTR(module);
    JSValue evaluation = JS_EvalFunction(
        domain->context,
        JS_DupValue(domain->context, module)
    );
    if (JS_IsException(evaluation)) {
        write_exception(domain, diagnostic, diagnostic_capacity);
        JS_FreeValue(domain->context, evaluation);
        JS_FreeValue(domain->context, module);
        return NULL;
    }
    JSPromiseStateEnum state = JS_PromiseState(domain->context, evaluation);
    if (state == JS_PROMISE_REJECTED) {
        JSValue reason = JS_PromiseResult(domain->context, evaluation);
        write_value_diagnostic(
            domain,
            reason,
            diagnostic,
            diagnostic_capacity,
            "SceneScript module evaluation rejected"
        );
        JS_FreeValue(domain->context, reason);
        JS_FreeValue(domain->context, evaluation);
        JS_FreeValue(domain->context, module);
        return NULL;
    }
    if (state == JS_PROMISE_PENDING) {
        write_diagnostic(
            diagnostic,
            diagnostic_capacity,
            "SceneScript top-level await is unsupported"
        );
        JS_FreeValue(domain->context, evaluation);
        JS_FreeValue(domain->context, module);
        return NULL;
    }
    JS_FreeValue(domain->context, evaluation);

    JSValue namespace = JS_GetModuleNamespace(domain->context, module_definition);
    JS_FreeValue(domain->context, module);
    if (JS_IsException(namespace)) {
        write_exception(domain, diagnostic, diagnostic_capacity);
        JS_FreeValue(domain->context, namespace);
        return NULL;
    }
    MWXSceneQuickJSOwner *owner = calloc(1, sizeof(*owner));
    if (owner == NULL) {
        JS_FreeValue(domain->context, namespace);
        write_diagnostic(diagnostic, diagnostic_capacity, "SceneScript owner allocation failed");
        return NULL;
    }
    owner->domain = domain;
    owner->module = namespace;
    owner->generation = generation;
    owner->material_function_layer = JS_UNDEFINED;
    owner->effect_names = calloc(1, sizeof(*owner->effect_names));
    if (owner->effect_names == NULL || !install_material_function_host(owner)) {
        free(owner->effect_names);
        JS_FreeValue(domain->context, owner->material_function_layer);
        JS_FreeValue(domain->context, owner->module);
        free(owner);
        write_diagnostic(diagnostic, diagnostic_capacity, "SceneScript host globals unavailable");
        return NULL;
    }
    return owner;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_configure_effect_catalog(
    MWXSceneQuickJSOwner *owner,
    uint32_t effect_count,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    clear_diagnostic(diagnostic, diagnostic_capacity);
    if (owner == NULL || owner->effect_names == NULL || owner->effect_count != 0 ||
        effect_count > MWX_SCENE_QUICKJS_MAX_EFFECTS) {
        write_diagnostic(diagnostic, diagnostic_capacity, "invalid effect catalog");
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    if (effect_count == 0) {
        return MWX_SCENE_QUICKJS_OK;
    }
    char **effect_names = calloc(effect_count, sizeof(*effect_names));
    if (effect_names == NULL) {
        write_diagnostic(diagnostic, diagnostic_capacity, "effect catalog allocation failed");
        return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    }
    free(owner->effect_names);
    owner->effect_names = effect_names;
    owner->effect_count = effect_count;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_set_effect_name(
    MWXSceneQuickJSOwner *owner,
    uint32_t effect_index,
    const char *name,
    size_t name_length,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    clear_diagnostic(diagnostic, diagnostic_capacity);
    if (owner == NULL || owner->effect_names == NULL || name == NULL ||
        effect_index >= owner->effect_count || name_length == 0 ||
        name_length > MWX_SCENE_QUICKJS_MAX_EFFECT_NAME ||
        memchr(name, '\0', name_length) != NULL ||
        owner->effect_names[effect_index] != NULL) {
        write_diagnostic(diagnostic, diagnostic_capacity, "invalid effect name");
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    char *copy = malloc(name_length + 1);
    if (copy == NULL) {
        write_diagnostic(diagnostic, diagnostic_capacity, "effect name allocation failed");
        return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    }
    memcpy(copy, name, name_length);
    copy[name_length] = '\0';
    owner->effect_names[effect_index] = copy;
    return MWX_SCENE_QUICKJS_OK;
}

void mwx_scene_quickjs_owner_destroy(MWXSceneQuickJSOwner *owner) {
    if (owner == NULL) {
        return;
    }
    if (owner->domain != NULL && owner->domain->context != NULL) {
        JS_FreeValue(owner->domain->context, owner->material_function_layer);
        JS_FreeValue(owner->domain->context, owner->module);
    }
    if (owner->effect_names != NULL) {
        for (uint32_t index = 0; index < owner->effect_count; ++index) {
            free(owner->effect_names[index]);
        }
        free(owner->effect_names);
    }
    free(owner);
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_update_scalar(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    double input,
    const MWXSceneQuickJSFrameInput *frame,
    double *output,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    return mwx_scene_quickjs_owner_update_scalar_with_user_properties(
        owner,
        expected_generation,
        input,
        frame,
        NULL,
        0,
        output,
        diagnostic,
        diagnostic_capacity
    );
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_update_scalar_with_user_properties(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    double input,
    const MWXSceneQuickJSFrameInput *frame,
    const char *user_properties_json,
    size_t user_properties_length,
    double *output,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    clear_diagnostic(diagnostic, diagnostic_capacity);
    if (owner == NULL || frame == NULL || output == NULL || !isfinite(input) ||
        !isfinite(frame->time_of_day) || frame->time_of_day < 0 ||
        frame->time_of_day > 1 || !isfinite(frame->frame_time) ||
        frame->frame_time < 0 || !isfinite(frame->runtime) || frame->runtime < 0) {
        write_diagnostic(diagnostic, diagnostic_capacity, "invalid SceneScript update argument");
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    if (owner->generation != expected_generation) {
        write_diagnostic(diagnostic, diagnostic_capacity, "stale SceneScript owner generation");
        return MWX_SCENE_QUICKJS_STALE_OWNER;
    }
    if (owner->disabled) {
        write_diagnostic(diagnostic, diagnostic_capacity, "SceneScript owner is disabled");
        return MWX_SCENE_QUICKJS_DISABLED;
    }
    MWXSceneQuickJSDomain *domain = owner->domain;
    domain->interrupted = false;
    owner->material_function_count = 0;
    owner->material_function_overflow = false;
    if (!owner->initialized) {
        JSValue init = JS_UNDEFINED;
        if (!get_function(owner, "init", &init, diagnostic, diagnostic_capacity)) {
            owner->disabled = true;
            return MWX_SCENE_QUICKJS_EXCEPTION;
        }
        if (JS_IsFunction(domain->context, init)) {
            MWXSceneQuickJSResult result = call_scalar(
                owner, init, input, frame,
                user_properties_json, user_properties_length,
                output, diagnostic, diagnostic_capacity
            );
            JS_FreeValue(domain->context, init);
            if (result != MWX_SCENE_QUICKJS_OK) {
                owner->disabled = true;
                return result;
            }
            input = *output;
        }
        owner->initialized = true;
    }
    JSValue update = JS_UNDEFINED;
    if (!get_function(owner, "update", &update, diagnostic, diagnostic_capacity)) {
        owner->disabled = true;
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    if (!JS_IsFunction(domain->context, update)) {
        *output = input;
        return MWX_SCENE_QUICKJS_OK;
    }
    MWXSceneQuickJSResult result = call_scalar(
        owner, update, input, frame,
        user_properties_json, user_properties_length,
        output, diagnostic, diagnostic_capacity
    );
    JS_FreeValue(domain->context, update);
    if (result != MWX_SCENE_QUICKJS_OK) {
        owner->disabled = true;
    }
    return result;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_update_vec3(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    const double input[3],
    const MWXSceneQuickJSFrameInput *frame,
    const char *script_properties_json,
    size_t script_properties_length,
    const char *user_properties_json,
    size_t user_properties_length,
    double output[3],
    char *diagnostic,
    size_t diagnostic_capacity
) {
    clear_diagnostic(diagnostic, diagnostic_capacity);
    if (owner == NULL || input == NULL || frame == NULL || output == NULL ||
        !isfinite(input[0]) || !isfinite(input[1]) || !isfinite(input[2]) ||
        !isfinite(frame->time_of_day) || frame->time_of_day < 0 ||
        frame->time_of_day > 1 || !isfinite(frame->frame_time) ||
        frame->frame_time < 0 || !isfinite(frame->runtime) || frame->runtime < 0) {
        write_diagnostic(diagnostic, diagnostic_capacity, "invalid SceneScript Vec3 update argument");
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    if (owner->generation != expected_generation) {
        write_diagnostic(diagnostic, diagnostic_capacity, "stale SceneScript owner generation");
        return MWX_SCENE_QUICKJS_STALE_OWNER;
    }
    if (owner->disabled) {
        write_diagnostic(diagnostic, diagnostic_capacity, "SceneScript owner is disabled");
        return MWX_SCENE_QUICKJS_DISABLED;
    }
    MWXSceneQuickJSDomain *domain = owner->domain;
    domain->interrupted = false;
    owner->material_function_count = 0;
    owner->material_function_overflow = false;
    double current[3] = {input[0], input[1], input[2]};
    if (!owner->initialized) {
        JSValue init = JS_UNDEFINED;
        if (!get_function(owner, "init", &init, diagnostic, diagnostic_capacity)) {
            owner->disabled = true;
            return MWX_SCENE_QUICKJS_EXCEPTION;
        }
        if (JS_IsFunction(domain->context, init)) {
            MWXSceneQuickJSResult result = call_vec3(
                owner, init, current, frame,
                script_properties_json, script_properties_length,
                user_properties_json, user_properties_length,
                current, diagnostic, diagnostic_capacity
            );
            JS_FreeValue(domain->context, init);
            if (result != MWX_SCENE_QUICKJS_OK) {
                owner->disabled = true;
                return result;
            }
        }
        owner->initialized = true;
    }
    JSValue update = JS_UNDEFINED;
    if (!get_function(owner, "update", &update, diagnostic, diagnostic_capacity)) {
        owner->disabled = true;
        return MWX_SCENE_QUICKJS_EXCEPTION;
    }
    if (!JS_IsFunction(domain->context, update)) {
        memcpy(output, current, sizeof(current));
        return MWX_SCENE_QUICKJS_OK;
    }
    MWXSceneQuickJSResult result = call_vec3(
        owner, update, current, frame,
        script_properties_json, script_properties_length,
        user_properties_json, user_properties_length,
        output, diagnostic, diagnostic_capacity
    );
    JS_FreeValue(domain->context, update);
    if (result != MWX_SCENE_QUICKJS_OK) {
        owner->disabled = true;
    }
    return result;
}

size_t mwx_scene_quickjs_owner_material_function_count(
    const MWXSceneQuickJSOwner *owner
) {
    return owner == NULL ? 0 : owner->material_function_count;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_material_function_at(
    const MWXSceneQuickJSOwner *owner,
    size_t index,
    uint32_t *effect_index,
    char *function_name,
    size_t function_name_capacity,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    clear_diagnostic(diagnostic, diagnostic_capacity);
    if (owner == NULL || effect_index == NULL || function_name == NULL ||
        function_name_capacity == 0 || index >= owner->material_function_count) {
        write_diagnostic(diagnostic, diagnostic_capacity, "invalid material function mutation");
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    const MWXSceneQuickJSMaterialFunctionMutationRecord *record =
        &owner->material_functions[index];
    size_t length = strlen(record->function_name);
    if (length + 1 > function_name_capacity) {
        write_diagnostic(diagnostic, diagnostic_capacity, "material function name buffer is too small");
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    *effect_index = record->effect_index;
    memcpy(function_name, record->function_name, length + 1);
    return MWX_SCENE_QUICKJS_OK;
}

void mwx_scene_quickjs_owner_invalidate(MWXSceneQuickJSOwner *owner) {
    if (owner != NULL) {
        owner->generation += 1;
        owner->disabled = true;
    }
}
