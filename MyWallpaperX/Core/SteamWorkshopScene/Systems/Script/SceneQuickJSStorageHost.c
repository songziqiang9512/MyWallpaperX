#include "SceneQuickJSInternal.h"

#include <stdlib.h>
#include <string.h>

static MWXSceneQuickJSOwner *active_storage_owner(JSContext *context) {
    MWXSceneQuickJSDomain *domain = JS_GetContextOpaque(context);
    if (domain == NULL || !domain->callback_active || !domain->frame_input_active ||
        domain->active_owner == NULL) {
        JS_ThrowTypeError(context, "localStorage is only available during a callback");
        return NULL;
    }
    if (domain->active_owner->teardown_started) {
        JS_ThrowTypeError(context, "localStorage is unavailable during teardown");
        return NULL;
    }
    return domain->active_owner;
}

static bool global_scope(JSContext *context, int argc, JSValueConst *argv, int index) {
    if (argc <= index || !JS_IsString(argv[index])) return false;
    size_t length = 0;
    const char *value = JS_ToCStringLen(context, &length, argv[index]);
    if (value == NULL) return false;
    const bool is_global = length == 6 && memcmp(value, "global", 6) == 0;
    JS_FreeCString(context, value);
    return is_global;
}

static char *copy_bytes(const char *value, size_t length) {
    char *copy = malloc(length + 1);
    if (copy == NULL) return NULL;
    if (length > 0) memcpy(copy, value, length);
    copy[length] = '\0';
    return copy;
}

static bool begin_transaction(MWXSceneQuickJSOwner *owner, bool is_global) {
    if (owner->storage_transaction_active) {
        return is_global || owner->storage_screen_identity != NULL;
    }
    MWXSceneQuickJSDomain *domain = owner->domain;
    owner->storage_transaction_active = true;
    if (domain->storage_screen_identity != NULL) {
        owner->storage_screen_identity = copy_bytes(
            domain->storage_screen_identity,
            strlen(domain->storage_screen_identity)
        );
        if (owner->storage_screen_identity == NULL) {
            owner->storage_transaction_active = false;
            return false;
        }
    }
    return is_global || owner->storage_screen_identity != NULL;
}

void mwx_scene_quickjs_owner_discard_storage_transaction(
    MWXSceneQuickJSOwner *owner
) {
    if (owner == NULL) return;
    for (size_t index = 0; index < owner->storage_mutation_count; ++index) {
        free(owner->storage_mutations[index].key);
        free(owner->storage_mutations[index].json);
        owner->storage_mutations[index].key = NULL;
        owner->storage_mutations[index].key_length = 0;
        owner->storage_mutations[index].json = NULL;
        owner->storage_mutations[index].json_length = 0;
    }
    owner->storage_mutation_count = 0;
    owner->storage_mutation_bytes = 0;
    owner->storage_mutation_overflow = false;
    owner->storage_transaction_active = false;
    free(owner->storage_screen_identity);
    owner->storage_screen_identity = NULL;
}

void mwx_scene_quickjs_destroy_storage_owner(MWXSceneQuickJSOwner *owner) {
    mwx_scene_quickjs_owner_discard_storage_transaction(owner);
}

static JSValue throw_storage_unavailable(
    JSContext *context,
    MWXSceneQuickJSOwner *owner,
    bool is_global
) {
    if (owner->domain->storage_read == NULL) {
        return JS_ThrowInternalError(context, "localStorage provider is unavailable");
    }
    if (!is_global && owner->storage_screen_identity == NULL) {
        return JS_ThrowTypeError(
            context,
            "screen localStorage requires an exact single-screen identity"
        );
    }
    return JS_ThrowOutOfMemory(context);
}

static bool read_key(
    JSContext *context,
    int argc,
    JSValueConst *argv,
    char **key,
    size_t *length
) {
    if (argc < 1 || !JS_IsString(argv[0])) {
        JS_ThrowTypeError(context, "localStorage key must be a string");
        return false;
    }
    const char *value = JS_ToCStringLen(context, length, argv[0]);
    if (value == NULL) return false;
    if (*length > MWX_SCENE_QUICKJS_MAX_STORAGE_KEY_BYTES ||
        memchr(value, '\0', *length) != NULL) {
        JS_FreeCString(context, value);
        JS_ThrowRangeError(context, "localStorage key exceeds 256 UTF-8 bytes");
        return false;
    }
    *key = copy_bytes(value, *length);
    JS_FreeCString(context, value);
    if (*key == NULL) {
        JS_ThrowOutOfMemory(context);
        return false;
    }
    return true;
}

static JSValue parse_stored_json(JSContext *context, const char *json, size_t length) {
    JSValue value = JS_ParseJSON(context, json, length, "localStorage");
    if (!JS_IsException(value)) return value;
    JSValue exception = JS_GetException(context);
    if (JS_IsNull(exception)) {
        return JS_Throw(context, exception);
    }
    JS_FreeValue(context, exception);
    return JS_UNDEFINED;
}

static JSValue staged_value(
    JSContext *context,
    MWXSceneQuickJSOwner *owner,
    bool is_global,
    const char *key,
    size_t key_length,
    bool *resolved
) {
    *resolved = false;
    for (size_t offset = owner->storage_mutation_count; offset > 0; --offset) {
        MWXSceneQuickJSStorageMutationRecord *record =
            &owner->storage_mutations[offset - 1];
        if (record->global_scope != is_global) continue;
        if (record->kind == MWX_SCENE_QUICKJS_STORAGE_CLEAR) {
            *resolved = true;
            return JS_UNDEFINED;
        }
        if (record->key_length != key_length ||
            memcmp(record->key, key, key_length) != 0) continue;
        *resolved = true;
        if (record->kind == MWX_SCENE_QUICKJS_STORAGE_DELETE) {
            return JS_UNDEFINED;
        }
        return parse_stored_json(context, record->json, record->json_length);
    }
    return JS_UNDEFINED;
}

static JSValue storage_get(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv
) {
    (void)this_value;
    MWXSceneQuickJSOwner *owner = active_storage_owner(context);
    if (owner == NULL) return JS_EXCEPTION;
    const bool is_global = global_scope(context, argc, argv, 1);
    if (!begin_transaction(owner, is_global) || owner->domain->storage_read == NULL) {
        return throw_storage_unavailable(context, owner, is_global);
    }
    char *key = NULL;
    size_t key_length = 0;
    if (!read_key(context, argc, argv, &key, &key_length)) return JS_EXCEPTION;
    bool resolved = false;
    JSValue staged = staged_value(
        context, owner, is_global, key, key_length, &resolved
    );
    if (resolved) {
        free(key);
        return staged;
    }
    size_t json_length = 0;
    const char *screen = owner->storage_screen_identity != NULL
        ? owner->storage_screen_identity : "";
    MWXSceneQuickJSStorageReadResult result = owner->domain->storage_read(
        owner->domain->storage_opaque,
        screen,
        strlen(screen),
        is_global ? 1 : 0,
        key,
        key_length,
        NULL,
        0,
        &json_length
    );
    if (result == MWX_SCENE_QUICKJS_STORAGE_READ_MISSING) {
        free(key);
        return JS_UNDEFINED;
    }
    if (result != MWX_SCENE_QUICKJS_STORAGE_READ_BUFFER_TOO_SMALL ||
        json_length > MWX_SCENE_QUICKJS_MAX_STORAGE_VALUE_BYTES) {
        free(key);
        return JS_ThrowInternalError(context, "localStorage read failed");
    }
    char *json = malloc(json_length + 1);
    if (json == NULL) {
        free(key);
        return JS_ThrowOutOfMemory(context);
    }
    const size_t expected_length = json_length;
    result = owner->domain->storage_read(
        owner->domain->storage_opaque,
        screen,
        strlen(screen),
        is_global ? 1 : 0,
        key,
        key_length,
        json,
        expected_length + 1,
        &json_length
    );
    free(key);
    if (result != MWX_SCENE_QUICKJS_STORAGE_READ_FOUND ||
        json_length != expected_length) {
        free(json);
        return JS_ThrowInternalError(context, "localStorage read changed during copy");
    }
    JSValue value = parse_stored_json(context, json, json_length);
    free(json);
    return value;
}

static JSValue append_mutation(
    JSContext *context,
    MWXSceneQuickJSOwner *owner,
    uint32_t kind,
    bool is_global,
    char *key,
    size_t key_length,
    char *json,
    size_t json_length
) {
    if (owner->storage_mutation_count >= MWX_SCENE_QUICKJS_MAX_STORAGE_MUTATIONS ||
        key_length > SIZE_MAX - json_length ||
        owner->storage_mutation_bytes > 262144u - key_length - json_length) {
        owner->storage_mutation_overflow = true;
        free(key);
        free(json);
        return JS_ThrowRangeError(context, "localStorage mutation budget exceeded");
    }
    MWXSceneQuickJSStorageMutationRecord *record =
        &owner->storage_mutations[owner->storage_mutation_count++];
    record->kind = kind;
    record->global_scope = is_global;
    record->key = key;
    record->key_length = key_length;
    record->json = json;
    record->json_length = json_length;
    owner->storage_mutation_bytes += key_length + json_length;
    return JS_UNDEFINED;
}

static JSValue storage_set(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv
) {
    (void)this_value;
    MWXSceneQuickJSOwner *owner = active_storage_owner(context);
    if (owner == NULL) return JS_EXCEPTION;
    if (owner->value_only || owner->domain->value_only_guard_active) {
        return JS_ThrowTypeError(context, "value-only owner cannot write localStorage");
    }
    const bool is_global = global_scope(context, argc, argv, 2);
    if (!begin_transaction(owner, is_global) || owner->domain->storage_read == NULL) {
        return throw_storage_unavailable(context, owner, is_global);
    }
    char *key = NULL;
    size_t key_length = 0;
    if (!read_key(context, argc, argv, &key, &key_length)) return JS_EXCEPTION;
    if (argc < 2 || JS_IsUndefined(argv[1])) {
        return append_mutation(
            context, owner, MWX_SCENE_QUICKJS_STORAGE_DELETE,
            is_global, key, key_length, NULL, 0
        );
    }
    JSValue encoded = JS_JSONStringify(
        context, argv[1], JS_UNDEFINED, JS_UNDEFINED
    );
    if (JS_IsException(encoded)) {
        free(key);
        return JS_EXCEPTION;
    }
    if (JS_IsUndefined(encoded)) {
        JS_FreeValue(context, encoded);
        free(key);
        return JS_ThrowTypeError(context, "localStorage value is not serializable");
    }
    size_t json_length = 0;
    const char *json_value = JS_ToCStringLen(context, &json_length, encoded);
    JS_FreeValue(context, encoded);
    if (json_value == NULL) {
        free(key);
        return JS_EXCEPTION;
    }
    if (json_length > MWX_SCENE_QUICKJS_MAX_STORAGE_VALUE_BYTES) {
        JS_FreeCString(context, json_value);
        free(key);
        return JS_ThrowRangeError(context, "localStorage value exceeds 64 KiB");
    }
    char *json = copy_bytes(json_value, json_length);
    JS_FreeCString(context, json_value);
    if (json == NULL) {
        free(key);
        return JS_ThrowOutOfMemory(context);
    }
    return append_mutation(
        context, owner, MWX_SCENE_QUICKJS_STORAGE_SET,
        is_global, key, key_length, json, json_length
    );
}

static JSValue storage_delete(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv
) {
    (void)this_value;
    MWXSceneQuickJSOwner *owner = active_storage_owner(context);
    if (owner == NULL) return JS_EXCEPTION;
    if (owner->value_only || owner->domain->value_only_guard_active) {
        return JS_ThrowTypeError(context, "value-only owner cannot write localStorage");
    }
    const bool is_global = global_scope(context, argc, argv, 1);
    if (!begin_transaction(owner, is_global) || owner->domain->storage_read == NULL) {
        return throw_storage_unavailable(context, owner, is_global);
    }
    JSValue current = storage_get(context, this_value, argc, argv);
    if (JS_IsException(current)) return current;
    const bool existed = !JS_IsUndefined(current);
    JS_FreeValue(context, current);
    char *key = NULL;
    size_t key_length = 0;
    if (!read_key(context, argc, argv, &key, &key_length)) return JS_EXCEPTION;
    if (!existed) {
        free(key);
        return JS_NewBool(context, false);
    }
    JSValue appended = append_mutation(
        context, owner, MWX_SCENE_QUICKJS_STORAGE_DELETE,
        is_global, key, key_length, NULL, 0
    );
    if (JS_IsException(appended)) return appended;
    return JS_NewBool(context, true);
}

static JSValue storage_clear(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv
) {
    (void)this_value;
    MWXSceneQuickJSOwner *owner = active_storage_owner(context);
    if (owner == NULL) return JS_EXCEPTION;
    if (owner->value_only || owner->domain->value_only_guard_active) {
        return JS_ThrowTypeError(context, "value-only owner cannot write localStorage");
    }
    const bool is_global = global_scope(context, argc, argv, 0);
    if (!begin_transaction(owner, is_global) || owner->domain->storage_read == NULL) {
        return throw_storage_unavailable(context, owner, is_global);
    }
    return append_mutation(
        context, owner, MWX_SCENE_QUICKJS_STORAGE_CLEAR,
        is_global, NULL, 0, NULL, 0
    );
}

bool mwx_scene_quickjs_install_storage_host(MWXSceneQuickJSDomain *domain) {
    JSContext *context = domain->context;
    JSValue storage = JS_NewObject(context);
    if (JS_IsException(storage)) return false;
    const struct { const char *name; JSCFunction *function; int argc; } methods[] = {
        {"get", storage_get, 2}, {"set", storage_set, 3},
        {"delete", storage_delete, 2}, {"clear", storage_clear, 1},
    };
    for (size_t index = 0; index < sizeof(methods) / sizeof(methods[0]); ++index) {
        JSValue function = JS_NewCFunction(
            context, methods[index].function, methods[index].name, methods[index].argc
        );
        if (JS_IsException(function) || JS_DefinePropertyValueStr(
                context, storage, methods[index].name, function,
                JS_PROP_ENUMERABLE
            ) < 0) {
            JS_FreeValue(context, storage);
            return false;
        }
    }
    if (JS_PreventExtensions(context, storage) < 0) {
        JS_FreeValue(context, storage);
        return false;
    }
    JSValue global = JS_GetGlobalObject(context);
    if (JS_IsException(global)) {
        JS_FreeValue(context, storage);
        return false;
    }
    const int flags = JS_PROP_ENUMERABLE;
    const bool installed =
        JS_DefinePropertyValueStr(context, global, "localStorage", storage, flags) >= 0 &&
        JS_DefinePropertyValueStr(
            context, global, "LOCATION_SCREEN", JS_NewString(context, "screen"), flags
        ) >= 0 &&
        JS_DefinePropertyValueStr(
            context, global, "LOCATION_GLOBAL", JS_NewString(context, "global"), flags
        ) >= 0;
    JS_FreeValue(context, global);
    return installed;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_configure_storage(
    MWXSceneQuickJSDomain *domain,
    MWXSceneQuickJSStorageRead read_callback,
    void *opaque,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->callback_active ||
        ((read_callback == NULL) != (opaque == NULL))) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "invalid localStorage provider configuration"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    domain->storage_read = read_callback;
    domain->storage_opaque = opaque;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_set_storage_screen_identity(
    MWXSceneQuickJSDomain *domain,
    const char *identity,
    size_t identity_length,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (domain == NULL || domain->callback_active || identity_length > 256 ||
        (identity_length > 0 && identity == NULL) ||
        (identity != NULL && memchr(identity, '\0', identity_length) != NULL)) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity,
            "invalid localStorage screen identity"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    char *replacement = NULL;
    if (identity_length > 0) {
        replacement = copy_bytes(identity, identity_length);
        if (replacement == NULL) {
            free(domain->storage_screen_identity);
            domain->storage_screen_identity = NULL;
            mwx_scene_quickjs_write_diagnostic(
                diagnostic, diagnostic_capacity,
                "localStorage screen identity allocation failed; identity cleared"
            );
            return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
        }
    }
    free(domain->storage_screen_identity);
    domain->storage_screen_identity = replacement;
    return MWX_SCENE_QUICKJS_OK;
}

size_t mwx_scene_quickjs_owner_storage_mutation_count(
    const MWXSceneQuickJSOwner *owner
) {
    return owner == NULL ? 0 : owner->storage_mutation_count;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_storage_mutation_at(
    const MWXSceneQuickJSOwner *owner,
    size_t index,
    MWXSceneQuickJSStorageMutation *mutation,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner == NULL || mutation == NULL ||
        index >= owner->storage_mutation_count ||
        !owner->storage_transaction_active) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid localStorage mutation index"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    const MWXSceneQuickJSStorageMutationRecord *record =
        &owner->storage_mutations[index];
    mutation->kind = record->kind;
    mutation->global_scope = record->global_scope ? 1 : 0;
    mutation->screen_identity = owner->storage_screen_identity;
    mutation->screen_identity_length = owner->storage_screen_identity == NULL
        ? 0 : strlen(owner->storage_screen_identity);
    mutation->key = record->key;
    mutation->key_length = record->key_length;
    mutation->json = record->json;
    mutation->json_length = record->json_length;
    return MWX_SCENE_QUICKJS_OK;
}
