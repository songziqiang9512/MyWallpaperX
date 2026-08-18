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

typedef struct MWXSceneQuickJSMaterialFunctionMutationRecord {
    uint32_t effect_index;
    char function_name[MWX_SCENE_QUICKJS_MAX_MATERIAL_FUNCTION_NAME];
} MWXSceneQuickJSMaterialFunctionMutationRecord;

struct MWXSceneQuickJSDomain {
    JSRuntime *runtime;
    JSContext *context;
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
    MWXSceneQuickJSMaterialFunctionMutationRecord material_functions[
        MWX_SCENE_QUICKJS_MAX_MATERIAL_FUNCTION_MUTATIONS
    ];
};

typedef struct MWXSceneQuickJSEffectHandle {
    MWXSceneQuickJSOwner *owner;
    uint32_t effect_index;
} MWXSceneQuickJSEffectHandle;

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
    if (owner == NULL || argc != 1) {
        return JS_ThrowTypeError(context, "getEffect expects one index");
    }
    int64_t index = -1;
    if (JS_ToInt64(context, &index, argv[0]) < 0 || index < 0 || index > UINT32_MAX) {
        return JS_ThrowTypeError(context, "getEffect index is invalid");
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
        JS_SetPropertyStr(context, effect, "executeMaterialFunction", callback) < 0) {
        JS_FreeValue(context, effect);
        return JS_EXCEPTION;
    }
    return effect;
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
    if (JS_IsException(getter) ||
        JS_SetPropertyStr(context, layer, "getEffect", getter) < 0) {
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
    JSValue argument = JS_NewFloat64(domain->context, input);
    JSValue result = JS_Call(
        domain->context,
        function,
        owner->module,
        1,
        &argument
    );
    JS_FreeValue(domain->context, argument);
    const bool restored = restore_material_function_host(owner, previous_global_layer);
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
    domain->context = JS_NewContext(domain->runtime);
    if (domain->context == NULL) {
        JS_FreeRuntime(domain->runtime);
        free(domain);
        write_diagnostic(diagnostic, diagnostic_capacity, "QuickJS context allocation failed");
        return NULL;
    }
    return domain;
}

void mwx_scene_quickjs_domain_destroy(MWXSceneQuickJSDomain *domain) {
    if (domain == NULL) {
        return;
    }
    if (domain->context != NULL) {
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
    if (!install_material_function_host(owner)) {
        JS_FreeValue(domain->context, owner->module);
        free(owner);
        write_diagnostic(diagnostic, diagnostic_capacity, "SceneScript material function host unavailable");
        return NULL;
    }
    return owner;
}

void mwx_scene_quickjs_owner_destroy(MWXSceneQuickJSOwner *owner) {
    if (owner == NULL) {
        return;
    }
    if (owner->domain != NULL && owner->domain->context != NULL) {
        JS_FreeValue(owner->domain->context, owner->material_function_layer);
        JS_FreeValue(owner->domain->context, owner->module);
    }
    free(owner);
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_update_scalar(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    double input,
    double *output,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    clear_diagnostic(diagnostic, diagnostic_capacity);
    if (owner == NULL || output == NULL || !isfinite(input)) {
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
                owner, init, input, output, diagnostic, diagnostic_capacity
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
        owner, update, input, output, diagnostic, diagnostic_capacity
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
