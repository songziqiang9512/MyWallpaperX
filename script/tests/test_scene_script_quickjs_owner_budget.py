#!/usr/bin/env python3

"""QuickJS owner-construction instruction budget regression gate."""

from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

try:
    from .scene_vector_vm_test_support import C_SOURCES
except ImportError:
    from scene_vector_vm_test_support import C_SOURCES


ROOT = Path(__file__).resolve().parents[2]
SCENE_SCRIPT = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script"
QUICKJS = SCENE_SCRIPT / "QuickJSNG"

HARNESS = r'''
#include "SceneQuickJS.h"
#include "SceneQuickJSInternal.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int layer_failure_after = -1;
static int particle_failure_after = -1;
static int native_failures = 0;
static uintptr_t watched_handle = 0;
static int watched_frees = 0;
static int watched_late_finalizers = 0;
static int namespace_headroom = -1;
static int namespace_failures = 0;
static int bind_headroom = -1;
static int bind_failures = 0;
static int install_headroom = -1;
static int install_failures = 0;
static int compile_headroom = -1;
static int compile_failures = 0;

JSValue mwx_fixture_compile(JSContext *context, const char *source, size_t length,
    const char *name, int flags) {
    const int headroom = compile_headroom;
    compile_headroom = -1;
    if (headroom >= 0) {
        JSMemoryUsage usage = {0};
        JS_ComputeMemoryUsage(JS_GetRuntime(context), &usage);
        JS_SetMemoryLimit(JS_GetRuntime(context), (size_t)usage.malloc_size + headroom);
    }
    JSValue value = JS_Eval(context, source, length, name, flags);
    if (headroom == -3) { JS_FreeValue(context, value); value = JS_EXCEPTION; }
    if (headroom == -2) JS_ThrowOutOfMemory(context);
    if (headroom != -1 && (JS_IsException(value) || JS_HasException(context)))
        compile_failures += 1;
    return value;
}

bool mwx_fixture_install_handles(MWXSceneQuickJSOwner *owner, const char **phase) {
    const int headroom = install_headroom;
    install_headroom = -1;
    if (headroom == -3) { install_failures += 1; return false; }
    if (headroom >= 0) {
        JSMemoryUsage usage = {0};
        JS_ComputeMemoryUsage(owner->domain->runtime, &usage);
        JS_SetMemoryLimit(owner->domain->runtime, (size_t)usage.malloc_size + headroom);
    }
    const bool installed = mwx_scene_quickjs_install_owner_handles(owner, phase);
    if (headroom == -2) JS_ThrowOutOfMemory(owner->domain->context);
    if (headroom != -1 && (!installed || JS_HasException(owner->domain->context)))
        install_failures += 1;
    return installed;
}

JSValue mwx_fixture_module_namespace(JSContext *context, JSModuleDef *module) {
    const int headroom = namespace_headroom;
    namespace_headroom = -1;
    if (headroom >= 0) {
        JSMemoryUsage usage = {0};
        JS_ComputeMemoryUsage(JS_GetRuntime(context), &usage);
        JS_SetMemoryLimit(JS_GetRuntime(context), (size_t)usage.malloc_size + headroom);
    }
    JSValue value = JS_GetModuleNamespace(context, module);
    if (headroom == -3) { JS_FreeValue(context, value); value = JS_EXCEPTION; }
    if (headroom == -2) JS_ThrowOutOfMemory(context);
    if (headroom != -1 && (JS_IsException(value) || JS_HasException(context)))
        namespace_failures += 1;
    return value;
}

bool mwx_fixture_bind_module_engine(MWXSceneQuickJSOwner *owner, JSValue *previous) {
    const int headroom = bind_headroom;
    bind_headroom = -1;
    if (headroom == -3) { bind_failures += 1; return false; }
    if (headroom >= 0) {
        JSMemoryUsage usage = {0};
        JS_ComputeMemoryUsage(owner->domain->runtime, &usage);
        JS_SetMemoryLimit(owner->domain->runtime, (size_t)usage.malloc_size + headroom);
    }
    const bool bound = mwx_scene_quickjs_bind_module_engine_host(owner, previous);
    if (headroom == -2) JS_ThrowOutOfMemory(owner->domain->context);
    if (headroom != -1 && (!bound || JS_HasException(owner->domain->context)))
        bind_failures += 1;
    return bound;
}

static JSValue arm_namespace_failure(JSContext *context, JSValueConst this_value,
    int argc, JSValueConst *argv) {
    (void)this_value;
    int32_t headroom = -1;
    if (argc != 1 || JS_ToInt32(context, &headroom, argv[0]) < 0 || headroom < -3)
        return JS_ThrowTypeError(context, "invalid fixture namespace headroom");
    namespace_headroom = headroom;
    return JS_UNDEFINED;
}

void mwx_fixture_layer_free(void *pointer) {
    if ((uintptr_t)pointer == watched_handle && watched_handle != 0) {
        MWXSceneQuickJSLayerAccessHandle *handle = pointer;
        watched_frees += 1;
        if (handle->construction_finalized != NULL && *handle->construction_finalized)
            watched_late_finalizers += 1;
    }
    free(pointer);
}

void *mwx_fixture_layer_calloc(size_t count, size_t size) {
    if (layer_failure_after >= 0 && layer_failure_after-- == 0) {
        native_failures += 1;
        return NULL;
    }
    return calloc(count, size);
}

void *mwx_fixture_particle_malloc(size_t size) {
    if (particle_failure_after >= 0 && particle_failure_after-- == 0) {
        native_failures += 1;
        return NULL;
    }
    return malloc(size);
}

static JSValue arm_layer_allocator(JSContext *context, JSValueConst this_value,
    int argc, JSValueConst *argv) {
    (void)this_value;
    int32_t ordinal = 0;
    if (argc != 1 || JS_ToInt32(context, &ordinal, argv[0]) < 0 || ordinal < 0)
        return JS_ThrowTypeError(context, "invalid fixture allocation ordinal");
    layer_failure_after = ordinal;
    return JS_UNDEFINED;
}

static JSValue arm_particle_allocator(JSContext *context, JSValueConst this_value,
    int argc, JSValueConst *argv) {
    (void)this_value;
    int32_t ordinal = 0;
    if (argc != 1 || JS_ToInt32(context, &ordinal, argv[0]) < 0 || ordinal < 0)
        return JS_ThrowTypeError(context, "invalid fixture particle allocation ordinal");
    particle_failure_after = ordinal;
    return JS_UNDEFINED;
}

static int check(int condition, const char *label, const char *diagnostic) {
    if (condition) return 0;
    fprintf(stderr, "FAIL %s: %s\n", label, diagnostic ? diagnostic : "");
    return 1;
}

static JSValue constrain_install_heap(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv
) {
    (void)this_value;
    int32_t headroom = 0;
    if (argc != 1 || JS_ToInt32(context, &headroom, argv[0]) < 0 || headroom < 0)
        return JS_ThrowTypeError(context, "invalid fixture headroom");
    JSMemoryUsage usage = {0};
    JS_ComputeMemoryUsage(JS_GetRuntime(context), &usage);
    JS_SetMemoryLimit(JS_GetRuntime(context), (size_t)usage.malloc_size + headroom);
    return JS_UNDEFINED;
}

static int host_install_memory_failure(void) {
    int failures = 0;
    int observed_install_failure = 0;
    const int headrooms[] = {512, 1024, 2048, 4096, 8192};
    for (size_t index = 0; index < sizeof(headrooms) / sizeof(headrooms[0]); ++index) {
        char diagnostic[512] = {0};
        MWXSceneQuickJSDomain *domain = mwx_scene_quickjs_domain_create(
            2 * 1024 * 1024, 512 * 1024, 100000,
            diagnostic, sizeof(diagnostic)
        );
        failures += check(domain != NULL, "install fixture domain", diagnostic);
        if (domain == NULL) continue;
        JSValue global = JS_GetGlobalObject(domain->context);
        const int installed = JS_SetPropertyStr(
            domain->context, global, "constrainInstallHeap",
            JS_NewCFunction(domain->context, constrain_install_heap,
                            "constrainInstallHeap", 1)
        );
        JS_FreeValue(domain->context, global);
        failures += check(installed >= 0, "install fixture host", diagnostic);
        char source[160];
        snprintf(source, sizeof(source),
                 "constrainInstallHeap(%d); export function update(value){return value;}",
                 headrooms[index]);
        MWXSceneQuickJSResult result = MWX_SCENE_QUICKJS_OK;
        MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_owner_create_with_budget(
            domain, source, strlen(source), 100 + index, 100000,
            &result, diagnostic, sizeof(diagnostic)
        );
        if (owner == NULL && strstr(diagnostic, "host installation failed") != NULL) {
            observed_install_failure += 1;
            failures += check(result == MWX_SCENE_QUICKJS_MEMORY_EXCEEDED,
                              "host install OOM retains typed cause", diagnostic);
            failures += check(strstr(diagnostic, "phase=") != NULL &&
                              strstr(diagnostic, "hasException=1") != NULL &&
                              strstr(diagnostic, "mallocBytes=") != NULL &&
                              strstr(diagnostic, "mallocLimit=") != NULL &&
                              strstr(diagnostic, "usedBytes=") != NULL &&
                              strstr(diagnostic, "ownerOrdinal=1") != NULL,
                              "host install failure exposes bounded measurements", diagnostic);
        }
        if (owner != NULL) mwx_scene_quickjs_owner_destroy(owner);
        mwx_scene_quickjs_domain_destroy(domain);
    }
    failures += check(observed_install_failure > 0,
                      "fixture reaches host install allocation failure", "");
    return failures;
}

static int host_install_accessor_boundary(void) {
    int failures = 0;
    char diagnostic[512] = {0};
    MWXSceneQuickJSDomain *domain = mwx_scene_quickjs_domain_create(
        2 * 1024 * 1024, 512 * 1024, 100000, diagnostic, sizeof(diagnostic)
    );
    failures += check(domain != NULL, "accessor fixture domain", diagnostic);
    if (domain == NULL) return failures;
    const char *prototype_source =
        "for(const name of ['getAnimation','getEffect','visible','getLayer','instance'])"
        "Object.defineProperty(Object.prototype,name,{get(){throw null;},"
        "set(){throw null;},configurable:true});"
        "export function update(value){return value;}";
    MWXSceneQuickJSResult result = MWX_SCENE_QUICKJS_EXCEPTION;
    MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_owner_create_with_budget(
        domain, prototype_source, strlen(prototype_source), 201, 100000,
        &result, diagnostic, sizeof(diagnostic)
    );
    failures += check(owner != NULL && result == MWX_SCENE_QUICKJS_OK,
                      "host factories define own properties without invoking authored accessors",
                      diagnostic);
    if (owner != NULL) mwx_scene_quickjs_owner_destroy(owner);
    const char *sources[] = {
        "Object.defineProperty(globalThis,'getProbe',{get(){throw null;}});"
            "void getProbe; export function update(value){return value;}",
        "Object.defineProperty(globalThis,'setProbe',{set(value){throw null;}});"
            "setProbe=1; export function update(value){return value;}",
    };
    for (size_t index = 0; index < sizeof(sources) / sizeof(sources[0]); ++index) {
        result = MWX_SCENE_QUICKJS_OK;
        owner = mwx_scene_quickjs_owner_create_with_budget(
            domain, sources[index], strlen(sources[index]), 202 + index, 100000,
            &result, diagnostic, sizeof(diagnostic)
        );
        failures += check(owner == NULL && result == MWX_SCENE_QUICKJS_EXCEPTION,
                          "authored accessor throw null remains an ordinary exception", diagnostic);
        if (owner != NULL) mwx_scene_quickjs_owner_destroy(owner);
    }
    mwx_scene_quickjs_domain_destroy(domain);
    return failures;
}

static int constructor_native_boundary(void) {
    int failures = 0;
    const char *formatters[] = {
        "Error.prototype.toString=function(){formatterCalls++;return 'ok';};",
        "Error.prototype.toString=function(){formatterCalls++;throw null;};",
        "Error.prototype[Symbol.toPrimitive]=function(){formatterCalls++;return 'ok';};",
        "Error.prototype[Symbol.toPrimitive]=function(){formatterCalls++;throw null;};",
    };
    const int headrooms[] = {-3, -2, 0, 64, 128, 256, 512, 1024, 2048};
    int observed_namespace = 0;
    int observed_bind = 0;
    int observed_install = 0;
    int observed_compile = 0;
    for (size_t mode = 0; mode < sizeof(formatters) / sizeof(formatters[0]); ++mode) {
        for (size_t index = 0; index < sizeof(headrooms) / sizeof(headrooms[0]); ++index) {
            for (int phase = 0; phase < 4; ++phase) {
                char diagnostic[512] = {0};
                MWXSceneQuickJSDomain *domain = mwx_scene_quickjs_domain_create(
                    2 * 1024 * 1024, 512 * 1024, 100000, diagnostic, sizeof(diagnostic)
                );
                failures += check(domain != NULL, "constructor boundary domain", diagnostic);
                if (domain == NULL) continue;
                JSValue global = JS_GetGlobalObject(domain->context);
                JS_SetPropertyStr(domain->context, global, "armNamespaceFailure",
                    JS_NewCFunction(domain->context, arm_namespace_failure, "armNamespaceFailure", 1));
                char setup[512];
                snprintf(setup, sizeof(setup),
                    "globalThis.formatterCalls=0;globalThis.evalCalls=0;%s export function update(value){return value;}",
                    formatters[mode]);
                MWXSceneQuickJSResult result = MWX_SCENE_QUICKJS_OK;
                MWXSceneQuickJSOwner *first = mwx_scene_quickjs_owner_create_with_budget(
                    domain, setup, strlen(setup), 800, 100000, &result, diagnostic, sizeof(diagnostic)
                );
                failures += check(first != NULL, "constructor prior formatter owner", diagnostic);
                char source[256];
                snprintf(source, sizeof(source),
                    "globalThis.evalCalls++;armNamespaceFailure(%d); export function update(renamedInput){return renamedInput;}",
                    phase == 0 ? headrooms[index] : -1);
                namespace_failures = 0;
                bind_failures = 0;
                install_failures = 0;
                compile_failures = 0;
                bind_headroom = phase == 1 ? headrooms[index] : -1;
                install_headroom = phase == 2 ? headrooms[index] : -1;
                compile_headroom = phase == 3 ? headrooms[index] : -1;
                if (headrooms[index] == -3 && mode >= 1) {
                    JSValue old = mode == 1 ? JS_NULL : JS_NewError(domain->context);
                    if (mode != 1) JS_DefinePropertyValueStr(domain->context, old, "message",
                        JS_NewString(domain->context, "out of memory"), JS_PROP_C_W_E);
                    JS_Throw(domain->context, old);
                }
                JSValue previous_engine = JS_DupValue(domain->context, domain->active_engine);
                MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_owner_create_with_budget(
                    domain, source, strlen(source), 801, 100000, &result, diagnostic, sizeof(diagnostic)
                );
                namespace_headroom = -1;
                bind_headroom = -1;
                install_headroom = -1;
                compile_headroom = -1;
                const int observed_counts[] = {namespace_failures, bind_failures, install_failures, compile_failures};
                const bool observed = observed_counts[phase] != 0;
                if (observed) {
                    observed_namespace += phase == 0;
                    observed_bind += phase == 1;
                    observed_install += phase == 2;
                    observed_compile += phase == 3;
                    const MWXSceneQuickJSResult expected = headrooms[index] == -3
                        ? (phase == 3 ? MWX_SCENE_QUICKJS_COMPILE_ERROR : MWX_SCENE_QUICKJS_EXCEPTION)
                        : MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
                    const char *phases[] = {"phase=namespace", "phase=engine-bind", "phase=", "phase=compile"};
                    failures += check(owner == NULL && result == expected &&
                                      strstr(diagnostic, phases[phase]) != NULL,
                                      "native constructor failure retains phase and typed memory", diagnostic);
                    failures += check(domain->module_owner == NULL && domain->active_owner == NULL &&
                                      !domain->value_only_guard_active && !JS_HasException(domain->context),
                                      "failed native caller clears new cause and leaves no dangling active owner", diagnostic);
                    if (phase == 3) {
                        JS_SetMemoryLimit(domain->runtime, 2 * 1024 * 1024);
                        JSValue calls = JS_GetPropertyStr(domain->context, global, "evalCalls");
                        int32_t evaluated = -1; JS_ToInt32(domain->context, &evaluated, calls);
                        failures += check(evaluated == 0 && domain->next_owner_identity == 1,
                                          "failed compile never enters owner allocation or authored eval", diagnostic);
                        JS_FreeValue(domain->context, calls);
                    }
                }
                JS_SetMemoryLimit(domain->runtime, 2 * 1024 * 1024);
                if (JS_HasException(domain->context)) {
                    JSValue pending = JS_GetException(domain->context);
                    JS_FreeValue(domain->context, pending);
                }
                JSValue calls = JS_GetPropertyStr(domain->context, global, "formatterCalls");
                int32_t called = -1;
                JS_ToInt32(domain->context, &called, calls);
                failures += check(called == 0, "native bind/namespace never executes prior formatter", diagnostic);
                JS_FreeValue(domain->context, calls);
                failures += check(JS_VALUE_GET_PTR(previous_engine) == JS_VALUE_GET_PTR(domain->active_engine),
                                  "native failures preserve original active engine identity", diagnostic);
                JS_FreeValue(domain->context, previous_engine);
                const char *healthy = "export function update(freshInput){return freshInput+1;}";
                MWXSceneQuickJSOwner *peer = mwx_scene_quickjs_owner_create_with_budget(
                    domain, healthy, strlen(healthy), 802, 100000, &result, diagnostic, sizeof(diagnostic));
                double output = 0;
                const MWXSceneQuickJSFrameInput frame = {.time_of_day=0.25,.frame_time=1.0/60,.runtime=2};
                failures += check(peer != NULL && mwx_scene_quickjs_owner_update_scalar(
                    peer, 802, 5, &frame, &output, diagnostic, sizeof(diagnostic)) == MWX_SCENE_QUICKJS_OK && output == 6,
                    "self-fixture cleanup probe keeps healthy peer usable", diagnostic);
                if (peer != NULL) mwx_scene_quickjs_owner_destroy(peer);
                JS_FreeValue(domain->context, global);
                if (owner != NULL) mwx_scene_quickjs_owner_destroy(owner);
                if (first != NULL) mwx_scene_quickjs_owner_destroy(first);
                mwx_scene_quickjs_domain_destroy(domain);
            }
        }
    }
    failures += check(observed_namespace > 4 && observed_bind > 4 && observed_install > 4 && observed_compile > 4,
                      "fixture reaches real finite-heap native failures and success-with-new-error negatives", "");
    char diagnostic[512] = {0};
    for (int kind = 0; kind < 2; ++kind) {
        MWXSceneQuickJSDomain *domain = mwx_scene_quickjs_domain_create(
            2 * 1024 * 1024, 512 * 1024, 100000, diagnostic, sizeof(diagnostic)
        );
        if (domain != NULL) {
            JSValue reported = kind == 0 ? JS_NULL : JS_NewError(domain->context);
            if (kind != 0) JS_DefinePropertyValueStr(domain->context, reported, "message",
                JS_NewString(domain->context, "out of memory"), JS_PROP_C_W_E);
            JSValue expected_old = JS_DupValue(domain->context, reported);
            JS_Throw(domain->context, reported);
            const char *source = "export function update(renamedInput){return renamedInput-(-1);}";
            MWXSceneQuickJSResult result = MWX_SCENE_QUICKJS_EXCEPTION;
            MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_owner_create_with_budget(
                domain, source, strlen(source), 899, 100000, &result, diagnostic, sizeof(diagnostic)
            );
            failures += check(owner != NULL && result == MWX_SCENE_QUICKJS_OK && JS_HasException(domain->context),
                              "old pending exception does not become native allocation failure", diagnostic);
            JSValue old = JS_GetException(domain->context);
            failures += check(kind == 0 ? JS_IsNull(old) :
                              JS_IsError(old) && JS_VALUE_GET_PTR(old) == JS_VALUE_GET_PTR(expected_old),
                              "successful native boundaries preserve exact old pending identity", diagnostic);
            JS_FreeValue(domain->context, old);
            JS_FreeValue(domain->context, expected_old);
            if (owner != NULL) mwx_scene_quickjs_owner_destroy(owner);
            mwx_scene_quickjs_domain_destroy(domain);
        } else failures += check(false, "old pending negative domain", diagnostic);
    }
    return failures;
}

static int compile_formatter_boundary(void) {
    int failures = 0;
    const char *formatters[] = {
        "Error.prototype.toString=function(){formatterCalls++;return 'out of memory';};",
        "Error.prototype.toString=function(){formatterCalls++;return 'ok';};",
        "Error.prototype.toString=function(){formatterCalls++;throw null;};",
        "Error.prototype[Symbol.toPrimitive]=function(){formatterCalls++;return 'out of memory';};",
        "Error.prototype[Symbol.toPrimitive]=function(){formatterCalls++;return 'ok';};",
        "Error.prototype[Symbol.toPrimitive]=function(){formatterCalls++;throw null;};",
    };
    const char *malformed[] = {
        "export function update( {",
        "export function update(renamedInput){return (;}",
    };
    for (size_t mode = 0; mode < sizeof(formatters) / sizeof(formatters[0]); ++mode) {
        char diagnostic[512] = {0};
        MWXSceneQuickJSDomain *domain = mwx_scene_quickjs_domain_create(
            2 * 1024 * 1024, 512 * 1024, 100000, diagnostic, sizeof(diagnostic)
        );
        failures += check(domain != NULL, "compile formatter domain", diagnostic);
        if (domain == NULL) continue;
        char setup[512];
        snprintf(setup, sizeof(setup),
            "globalThis.formatterCalls=0;%s export function update(renamedInput){return renamedInput;}",
            formatters[mode]);
        MWXSceneQuickJSResult result = MWX_SCENE_QUICKJS_OK;
        MWXSceneQuickJSOwner *formatter_owner = mwx_scene_quickjs_owner_create_with_budget(
            domain, setup, strlen(setup), 500 + mode, 100000,
            &result, diagnostic, sizeof(diagnostic)
        );
        failures += check(formatter_owner != NULL && result == MWX_SCENE_QUICKJS_OK,
                          "prior owner installs formatter", diagnostic);
        for (size_t index = 0; index < sizeof(malformed) / sizeof(malformed[0]); ++index) {
            MWXSceneQuickJSOwner *invalid = mwx_scene_quickjs_owner_create_with_budget(
                domain, malformed[index], strlen(malformed[index]), 600 + index, 100000,
                &result, diagnostic, sizeof(diagnostic)
            );
            failures += check(invalid == NULL && result == MWX_SCENE_QUICKJS_COMPILE_ERROR,
                              "native syntax error cannot be relabeled by prior formatter", diagnostic);
            if (invalid != NULL) mwx_scene_quickjs_owner_destroy(invalid);
        }
        char oversized[32769];
        const char *prefix = "export function update(renamedInput){return '";
        size_t prefix_length = strlen(prefix);
        memcpy(oversized, prefix, prefix_length);
        memset(oversized + prefix_length, 'q', 32000);
        memcpy(oversized + prefix_length + 32000, "';}", 4);
        int observed_native_error = 0;
        const int parser_headrooms[] = {2048, 4096, 8192};
        for (size_t index = 0; index < sizeof(parser_headrooms) / sizeof(parser_headrooms[0]); ++index) {
            JSMemoryUsage parser_usage = {0};
            JS_ComputeMemoryUsage(domain->runtime, &parser_usage);
            JS_SetMemoryLimit(domain->runtime,
                (size_t)parser_usage.malloc_size + parser_headrooms[index]);
            JSValue parse = JS_Eval(domain->context, oversized, strlen(oversized),
                "renamed-error-probe.scene.js", JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY);
            failures += check(JS_IsException(parse), "large literal exceeds finite parser headroom", "");
            JSValue native_error = JS_GetException(domain->context);
            observed_native_error += JS_IsError(native_error);
            JS_FreeValue(domain->context, native_error);
            JS_FreeValue(domain->context, parse);
            MWXSceneQuickJSOwner *overflow = mwx_scene_quickjs_owner_create_with_budget(
                domain, oversized, strlen(oversized), 650 + index, 100000,
                &result, diagnostic, sizeof(diagnostic)
            );
            failures += check(overflow == NULL && result == MWX_SCENE_QUICKJS_MEMORY_EXCEEDED &&
                              strstr(diagnostic, "phase=compile") != NULL,
                              "native compile Error stays typed memory despite prior formatter", diagnostic);
            if (overflow != NULL) mwx_scene_quickjs_owner_destroy(overflow);
            JS_SetMemoryLimit(domain->runtime, 2 * 1024 * 1024);
        }
        failures += check(observed_native_error > 0,
                          "parser fixture reaches non-null native Error allocation failure", "");
        const char *valid = "export function update(value){return value;}";
        JSMemoryUsage usage = {0};
        JS_ComputeMemoryUsage(domain->runtime, &usage);
        JS_SetMemoryLimit(domain->runtime, (size_t)usage.malloc_size);
        JSValue probe = JS_Eval(domain->context, valid, strlen(valid),
            "renamed-null-probe.scene.js", JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY);
        failures += check(JS_IsException(probe), "zero-headroom compile fails", "");
        JSValue sentinel = JS_GetException(domain->context);
        failures += check(JS_IsNull(sentinel), "native parser exposes null allocation sentinel", "");
        JS_FreeValue(domain->context, sentinel);
        JS_FreeValue(domain->context, probe);
        MWXSceneQuickJSOwner *excess = mwx_scene_quickjs_owner_create_with_budget(
            domain, valid, strlen(valid), 700 + mode, 100000,
            &result, diagnostic, sizeof(diagnostic)
        );
        failures += check(excess == NULL && result == MWX_SCENE_QUICKJS_MEMORY_EXCEEDED,
                          "native compile null sentinel remains typed memory failure", diagnostic);
        if (excess != NULL) mwx_scene_quickjs_owner_destroy(excess);
        JS_SetMemoryLimit(domain->runtime, 2 * 1024 * 1024);
        JSValue global = JS_GetGlobalObject(domain->context);
        JSValue calls = JS_GetPropertyStr(domain->context, global, "formatterCalls");
        int32_t called = -1;
        JS_ToInt32(domain->context, &called, calls);
        failures += check(called == 0, "native compile failures never execute prior formatter", diagnostic);
        JS_FreeValue(domain->context, calls);
        JS_FreeValue(domain->context, global);
        if (formatter_owner != NULL) mwx_scene_quickjs_owner_destroy(formatter_owner);
        mwx_scene_quickjs_domain_destroy(domain);
    }
    return failures;
}

static int native_factory_formatter_boundary(void) {
    int failures = 0;
    int observed_failures = 0;
    const char *formatters[] = {
        "Error.prototype.toString=function(){formatterCalls++;return 'ok';};",
        "Error.prototype.toString=function(){formatterCalls++;throw null;};",
        "Error.prototype[Symbol.toPrimitive]=function(){formatterCalls++;return 'ok';};",
        "Error.prototype[Symbol.toPrimitive]=function(){formatterCalls++;throw null;};",
    };
    for (size_t mode = 0; mode < sizeof(formatters) / sizeof(formatters[0]); ++mode) {
        for (int ordinal = -1; ordinal < 44; ++ordinal) {
            layer_failure_after = -1;
            particle_failure_after = -1;
            native_failures = 0;
            char diagnostic[512] = {0};
            MWXSceneQuickJSDomain *domain = mwx_scene_quickjs_domain_create(
                2 * 1024 * 1024, 512 * 1024, 100000, diagnostic, sizeof(diagnostic)
            );
            failures += check(domain != NULL, "native formatter domain", diagnostic);
            if (domain == NULL) continue;
            JSValue global = JS_GetGlobalObject(domain->context);
            JS_SetPropertyStr(domain->context, global, "armLayerAllocator",
                JS_NewCFunction(domain->context, arm_layer_allocator, "armLayerAllocator", 1));
            JS_SetPropertyStr(domain->context, global, "armParticleAllocator",
                JS_NewCFunction(domain->context, arm_particle_allocator, "armParticleAllocator", 1));
            char source[512];
            snprintf(source, sizeof(source),
                "globalThis.formatterCalls=0;%s %s(%d);"
                "export function update(renamedInput){return renamedInput;}",
                formatters[mode], ordinal < 0 ? "armParticleAllocator" : "armLayerAllocator",
                ordinal < 0 ? 0 : ordinal);
            MWXSceneQuickJSResult result = MWX_SCENE_QUICKJS_OK;
            MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_owner_create_with_budget(
                domain, source, strlen(source), 300 + ordinal, 100000,
                &result, diagnostic, sizeof(diagnostic)
            );
            layer_failure_after = -1;
            particle_failure_after = -1;
            if (native_failures != 0) {
                observed_failures += 1;
                failures += check(owner == NULL && result == MWX_SCENE_QUICKJS_MEMORY_EXCEEDED,
                                  "concrete native allocation failure stays typed", diagnostic);
                // Receiver identity and the two material lookup callables are
                // constructed before installation advances to the layer phase.
                const char *phase = ordinal >= 0 && ordinal < 3
                    ? "phase=effect" : "phase=layer";
                failures += check(strstr(diagnostic, phase) != NULL &&
                                  strstr(diagnostic, "hasException=1") != NULL,
                                  "native allocation failure has installation provenance", diagnostic);
            }
            JSValue calls = JS_GetPropertyStr(domain->context, global, "formatterCalls");
            int32_t called = -1;
            JS_ToInt32(domain->context, &called, calls);
            failures += check(called == 0, "native classification never executes Error formatter", diagnostic);
            JS_FreeValue(domain->context, calls);
            JS_FreeValue(domain->context, global);
            if (owner != NULL) mwx_scene_quickjs_owner_destroy(owner);
            mwx_scene_quickjs_domain_destroy(domain);
        }
    }
    failures += check(observed_failures > 128,
                      "fault sweep reaches property and later native payload producers", "");
    return failures;
}

static JSValue fixture_noop(JSContext *context, JSValueConst this_value,
    int argc, JSValueConst *argv, int magic, void *opaque) {
    (void)context; (void)this_value; (void)argc; (void)argv; (void)magic; (void)opaque;
    return JS_UNDEFINED;
}

static int closure_transfer_failure_boundary(void) {
    int failures = 0;
    int early_failures = 0;
    int late_failures = 0;
    const int headrooms[] = {0, 64, 128, 256, 512, 1024, 2048};
    char name[32769];
    memset(name, 'q', sizeof(name) - 1);
    name[sizeof(name) - 1] = '\0';
    for (size_t index = 0; index < sizeof(headrooms) / sizeof(headrooms[0]); ++index) {
        char diagnostic[512] = {0};
        MWXSceneQuickJSDomain *domain = mwx_scene_quickjs_domain_create(
            2 * 1024 * 1024, 512 * 1024, 100000, diagnostic, sizeof(diagnostic)
        );
        failures += check(domain != NULL, "closure transfer domain", diagnostic);
        if (domain == NULL) continue;
        MWXSceneQuickJSLayerAccessHandle *handle = calloc(1, sizeof(*handle));
        watched_handle = (uintptr_t)handle;
        watched_frees = 0;
        watched_late_finalizers = 0;
        JSMemoryUsage usage = {0};
        JS_ComputeMemoryUsage(domain->runtime, &usage);
        JS_SetMemoryLimit(domain->runtime, (size_t)usage.malloc_size + headrooms[index]);
        JSValue function = mwx_scene_quickjs_layer_access_closure(
            domain->context, fixture_noop, name, 0, 0, handle
        );
        failures += check(JS_IsException(function), "closure allocation fails within finite headroom", "");
        JS_FreeValue(domain->context, function);
        failures += check(watched_frees == 1, "opaque payload released exactly once", "");
        early_failures += watched_frees == 1 && watched_late_finalizers == 0;
        late_failures += watched_late_finalizers == 1;
        watched_handle = 0;
        mwx_scene_quickjs_domain_destroy(domain);
    }
    failures += check(early_failures > 0 && late_failures > 0,
                      "transfer tests reach both early caller release and late finalizer", "");
    char diagnostic[512] = {0};
    MWXSceneQuickJSDomain *domain = mwx_scene_quickjs_domain_create(
        2 * 1024 * 1024, 512 * 1024, 100000, diagnostic, sizeof(diagnostic)
    );
    failures += check(domain != NULL, "successful closure transfer domain", diagnostic);
    if (domain != NULL) {
        MWXSceneQuickJSLayerAccessHandle *handle = calloc(1, sizeof(*handle));
        watched_handle = (uintptr_t)handle;
        watched_frees = 0;
        watched_late_finalizers = 0;
        JSValue function = mwx_scene_quickjs_layer_access_closure(
            domain->context, fixture_noop, "renamedClosure", 0, 0, handle
        );
        failures += check(!JS_IsException(function) &&
                          handle->construction_finalized == NULL && watched_frees == 0,
                          "successful closure clears temporary construction pointer", "");
        JS_FreeValue(domain->context, function);
        failures += check(watched_frees == 1 && watched_late_finalizers == 0,
                          "published closure releases payload without stale stack access", "");
        watched_handle = 0;
        mwx_scene_quickjs_domain_destroy(domain);
    }
    return failures;
}

static MWXSceneQuickJSResult update(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    double input,
    double *output,
    char diagnostic[512]
) {
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
    };
    return mwx_scene_quickjs_owner_update_scalar(
        owner, generation, input, &frame, output, diagnostic, 512
    );
}

static int many_owner_capacity(void) {
    const size_t positive_owner_count = 1200;
    const size_t attempted_owner_limit = 4096;
    MWXSceneQuickJSOwner *owners[4096] = {0};
    int failures = 0;
    char diagnostic[512] = {0};
    MWXSceneQuickJSDomain *domain = mwx_scene_quickjs_domain_create(
        32 * 1024 * 1024, 512 * 1024, 100000, diagnostic, sizeof(diagnostic)
    );
    failures += check(domain != NULL, "finite many-owner domain", diagnostic);
    if (domain == NULL) return failures;
    const char *sources[] = {
        "export function update(value){return value+1;}",
        "export function update(renamedInput){return renamedInput-(-1);}",
    };
    size_t constructed = 0;
    int observed_heap_limit = 0;
    for (size_t index = 0; index < attempted_owner_limit; ++index) {
        const char *source = sources[index % 2];
        MWXSceneQuickJSResult result = MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
        owners[index] = mwx_scene_quickjs_owner_create_with_budget(
            domain, source, strlen(source), 1000 + index, 100000,
            &result, diagnostic, sizeof(diagnostic)
        );
        if (owners[index] == NULL) {
            char failure_details[640];
            snprintf(failure_details, sizeof(failure_details),
                     "constructed=%zu code=%u %s", constructed, (unsigned)result, diagnostic);
            failures += check(constructed >= positive_owner_count &&
                              result == MWX_SCENE_QUICKJS_MEMORY_EXCEEDED,
                              "finite heap rejects excess owners with typed memory failure",
                              failure_details);
            observed_heap_limit = 1;
            break;
        }
        failures += check(result == MWX_SCENE_QUICKJS_OK,
                          "valid many-owner construction", diagnostic);
        constructed += 1;
        if (constructed == 935 || constructed == positive_owner_count) {
            double output = 0;
            mwx_scene_quickjs_domain_reset_budget(domain, 100000);
            result = update(owners[index], 1000 + index, 5, &output, diagnostic);
            failures += check(result == MWX_SCENE_QUICKJS_OK && output == 6,
                              "935 and higher owner cohorts execute callbacks", diagnostic);
        }
    }
    failures += check(constructed >= positive_owner_count,
                      "935 and higher owner cohorts fit finite heap", diagnostic);
    failures += check(observed_heap_limit, "shared heap remains bounded", diagnostic);
    for (size_t index = 0; index < constructed; ++index)
        mwx_scene_quickjs_owner_destroy(owners[index]);
    mwx_scene_quickjs_domain_destroy(domain);
    return failures;
}

int main(void) {
    int failures = host_install_memory_failure() + host_install_accessor_boundary()
        + compile_formatter_boundary() + constructor_native_boundary()
        + native_factory_formatter_boundary() + closure_transfer_failure_boundary()
        + many_owner_capacity();
    char diagnostic[512] = {0};
    const uint64_t owner_budget = 160;
    MWXSceneQuickJSDomain *domain = mwx_scene_quickjs_domain_create(
        2 * 1024 * 1024, 512 * 1024, owner_budget,
        diagnostic, sizeof(diagnostic)
    );
    failures += check(domain != NULL, "domain create", diagnostic);
    if (domain == NULL) return 1;

    const char *work_source =
        "let total=0;"
        "for(let index=0;index<600000;++index){total+=index;}"
        "export function update(value){return value+(total>=0?1:0);}";
    MWXSceneQuickJSOwner *first = mwx_scene_quickjs_owner_create(
        domain, work_source, strlen(work_source), 1,
        diagnostic, sizeof(diagnostic)
    );
    failures += check(first != NULL, "first bounded owner", diagnostic);

    diagnostic[0] = '\0';
    MWXSceneQuickJSOwner *second = mwx_scene_quickjs_owner_create(
        domain, work_source, strlen(work_source), 2,
        diagnostic, sizeof(diagnostic)
    );
    failures += check(
        second != NULL,
        "later owner receives independent construction budget",
        diagnostic
    );

    const char *infinite_source =
        "for(;;){} export function update(value){return value;}";
    MWXSceneQuickJSResult creation_result = MWX_SCENE_QUICKJS_OK;
    diagnostic[0] = '\0';
    MWXSceneQuickJSOwner *over_budget =
        mwx_scene_quickjs_owner_create_with_budget(
            domain, infinite_source, strlen(infinite_source), 3, 2,
            &creation_result, diagnostic, sizeof(diagnostic)
        );
    failures += check(
        over_budget == NULL &&
            creation_result == MWX_SCENE_QUICKJS_BUDGET_EXCEEDED,
        "single owner construction budget is typed",
        diagnostic
    );

    const char *syntax_error = "export function update( {";
    creation_result = MWX_SCENE_QUICKJS_OK;
    diagnostic[0] = '\0';
    MWXSceneQuickJSOwner *invalid =
        mwx_scene_quickjs_owner_create_with_budget(
            domain, syntax_error, strlen(syntax_error), 4, owner_budget,
            &creation_result, diagnostic, sizeof(diagnostic)
        );
    failures += check(
        invalid == NULL && creation_result == MWX_SCENE_QUICKJS_COMPILE_ERROR,
        "syntax failure remains compile error",
        diagnostic
    );

    const char *throw_null_source = "throw null; export function update(value){return value;}";
    creation_result = MWX_SCENE_QUICKJS_OK;
    diagnostic[0] = '\0';
    MWXSceneQuickJSOwner *throw_null = mwx_scene_quickjs_owner_create_with_budget(
        domain, throw_null_source, strlen(throw_null_source), 40, owner_budget,
        &creation_result, diagnostic, sizeof(diagnostic)
    );
    failures += check(throw_null == NULL && creation_result == MWX_SCENE_QUICKJS_EXCEPTION,
                      "authored throw null is not a host allocation failure", diagnostic);

    const char *callback_source =
        "export function update(value){for(;;){}}";
    creation_result = MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    diagnostic[0] = '\0';
    MWXSceneQuickJSOwner *callback =
        mwx_scene_quickjs_owner_create_with_budget(
            domain, callback_source, strlen(callback_source), 5, owner_budget,
            &creation_result, diagnostic, sizeof(diagnostic)
        );
    failures += check(
        callback != NULL && creation_result == MWX_SCENE_QUICKJS_OK,
        "callback owner create",
        diagnostic
    );
    if (callback != NULL) {
        double output = 0;
        mwx_scene_quickjs_domain_reset_budget(domain, 2);
        diagnostic[0] = '\0';
        MWXSceneQuickJSResult callback_result = update(
            callback, 5, 1, &output, diagnostic
        );
        failures += check(
            callback_result == MWX_SCENE_QUICKJS_BUDGET_EXCEEDED,
            "frame callback budget remains typed",
            diagnostic
        );
    }

    diagnostic[0] = '\0';
    MWXSceneQuickJSOwner *after_callback = mwx_scene_quickjs_owner_create(
        domain,
        "export function update(value){return value+2;}",
        strlen("export function update(value){return value+2;}"),
        6,
        diagnostic,
        sizeof(diagnostic)
    );
    failures += check(
        after_callback != NULL,
        "callback exhaustion does not poison owner construction",
        diagnostic
    );
    if (after_callback != NULL) {
        double output = 0;
        mwx_scene_quickjs_domain_reset_budget(domain, owner_budget);
        diagnostic[0] = '\0';
        MWXSceneQuickJSResult result = update(
            after_callback, 6, 3, &output, diagnostic
        );
        failures += check(
            result == MWX_SCENE_QUICKJS_OK && output == 5,
            "frame budget reset remains independent",
            diagnostic
        );
    }

    if (after_callback != NULL) mwx_scene_quickjs_owner_destroy(after_callback);
    if (callback != NULL) mwx_scene_quickjs_owner_destroy(callback);
    if (invalid != NULL) mwx_scene_quickjs_owner_destroy(invalid);
    if (throw_null != NULL) mwx_scene_quickjs_owner_destroy(throw_null);
    if (over_budget != NULL) mwx_scene_quickjs_owner_destroy(over_budget);
    if (second != NULL) mwx_scene_quickjs_owner_destroy(second);
    if (first != NULL) mwx_scene_quickjs_owner_destroy(first);
    mwx_scene_quickjs_domain_destroy(domain);
    return failures == 0 ? 0 : 1;
}
'''


class SceneScriptQuickJSOwnerBudgetTest(unittest.TestCase):
    def test_owner_construction_budget_is_independent_and_typed(self) -> None:
        clang = shutil.which("clang")
        if clang is None:
            raise unittest.SkipTest("clang is required for the QuickJS budget gate")
        with tempfile.TemporaryDirectory(
            prefix="mwx-scene-quickjs-owner-budget-"
        ) as temporary_directory:
            root = Path(temporary_directory)
            harness = root / "harness.c"
            binary = root / "harness"
            harness.write_text(HARNESS, encoding="utf-8")
            # Keep failure injection on the complete former layer-host
            # responsibility after moving its native allocation/finalizers.
            layer_sources = [source for source in C_SOURCES
                if (source.name.startswith("SceneQuickJSLayer")
                    and source.name != "SceneQuickJSLayerSnapshotHost.c")
                or source.name == "SceneQuickJSPuppetBoneHost.c"]
            layer_objects = []
            for source in layer_sources:
                layer_object = root / f"{source.stem}.o"
                layer_compilation = subprocess.run(
                    [clang, "-std=c11", "-O0", "-I", str(SCENE_SCRIPT), "-I", str(QUICKJS),
                     "-Dcalloc=mwx_fixture_layer_calloc", "-Dfree=mwx_fixture_layer_free", "-c",
                     str(source), "-o", str(layer_object)],
                    cwd=ROOT, capture_output=True, text=True,
                )
                self.assertEqual(layer_compilation.returncode, 0,
                                 layer_compilation.stdout + layer_compilation.stderr)
                layer_objects.append(layer_object)
            particle_object = root / "particle-instance-host.o"
            particle_compilation = subprocess.run(
                [
                    clang, "-std=c11", "-O0", "-I", str(SCENE_SCRIPT), "-I", str(QUICKJS),
                    "-Dmalloc=mwx_fixture_particle_malloc", "-c",
                    str(SCENE_SCRIPT / "SceneQuickJSParticleInstanceHost.c"),
                    "-o", str(particle_object),
                ],
                cwd=ROOT, capture_output=True, text=True,
            )
            self.assertEqual(particle_compilation.returncode, 0,
                             particle_compilation.stdout + particle_compilation.stderr)
            owner_object = root / "owner.o"
            owner_compilation = subprocess.run(
                [clang, "-std=c11", "-O0", "-I", str(SCENE_SCRIPT), "-I", str(QUICKJS),
                 "-DJS_GetModuleNamespace=mwx_fixture_module_namespace",
                 "-DJS_Eval=mwx_fixture_compile",
                 "-Dmwx_scene_quickjs_install_owner_handles=mwx_fixture_install_handles",
                 "-Dmwx_scene_quickjs_bind_module_engine_host=mwx_fixture_bind_module_engine",
                 "-c", str(SCENE_SCRIPT / "SceneQuickJS.c"), "-o", str(owner_object)],
                cwd=ROOT, capture_output=True, text=True,
            )
            self.assertEqual(owner_compilation.returncode, 0,
                             owner_compilation.stdout + owner_compilation.stderr)
            command = [
                clang,
                "-std=c11",
                "-O0",
                "-I",
                str(SCENE_SCRIPT),
                "-I",
                str(QUICKJS),
                str(owner_object),
                *map(str, layer_objects),
                str(particle_object),
                *(str(source) for source in C_SOURCES
                  if source not in layer_sources
                  and source.name not in {"SceneQuickJS.c", "SceneQuickJSParticleInstanceHost.c"}),
                str(harness),
                "-lm",
                "-o",
                str(binary),
            ]
            compilation = subprocess.run(
                command, cwd=ROOT, capture_output=True, text=True
            )
            self.assertEqual(
                compilation.returncode,
                0,
                compilation.stdout + compilation.stderr,
            )
            execution = subprocess.run(
                [str(binary)], cwd=ROOT, capture_output=True, text=True
            )
            self.assertEqual(
                execution.returncode,
                0,
                execution.stdout + execution.stderr,
            )


if __name__ == "__main__":
    unittest.main()
