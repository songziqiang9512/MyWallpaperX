#include "SceneQuickJSInternal.h"

#include <math.h>
#include <float.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

typedef struct MWXSceneQuickJSAssetHandle {
    char *path;
} MWXSceneQuickJSAssetHandle;

void mwx_scene_quickjs_layer_finalize_asset_handle(JSRuntime *runtime, JSValue value) {
    (void)runtime;
    MWXSceneQuickJSAssetHandle *handle = JS_GetOpaque(
        value, JS_GetClassID(value)
    );
    if (handle == NULL) return;
    free(handle->path);
    free(handle);
}

bool mwx_scene_quickjs_layer_valid_asset_path(const char *path, size_t length, size_t maximum_length) {
    if (path == NULL || length == 0 ||
        length > maximum_length ||
        path[0] == '/' || path[0] == '\\' ||
        memchr(path, '\0', length) != NULL ||
        memchr(path, '\\', length) != NULL) return false;
    size_t segment_start = 0;
    for (size_t index = 0; index <= length; ++index) {
        if (index != length && path[index] != '/') continue;
        const size_t segment_length = index - segment_start;
        if (segment_length == 0 ||
            (segment_length == 1 && path[segment_start] == '.') ||
            (segment_length == 2 && path[segment_start] == '.' &&
             path[segment_start + 1] == '.')) return false;
        segment_start = index + 1;
    }
    return true;
}

JSValue mwx_scene_quickjs_layer_make_asset_handle(
    JSContext *context,
    MWXSceneQuickJSDomain *domain,
    const char *path,
    size_t length
) {
    if (!mwx_scene_quickjs_layer_valid_asset_path(path, length, MWX_SCENE_QUICKJS_MAX_LAYER_ASSET_PATH)) return JS_UNDEFINED;
    MWXSceneQuickJSAssetHandle *handle = calloc(1, sizeof(*handle));
    if (handle == NULL) return JS_EXCEPTION;
    handle->path = malloc(length + 1);
    if (handle->path == NULL) {
        free(handle);
        return JS_EXCEPTION;
    }
    memcpy(handle->path, path, length);
    handle->path[length] = '\0';
    JSValue value = JS_NewObjectClass(context, domain->asset_handle_class_id);
    if (JS_IsException(value) || JS_SetOpaque(value, handle) < 0) {
        free(handle->path);
        free(handle);
        JS_FreeValue(context, value);
        return JS_EXCEPTION;
    }
    return value;
}

const char *mwx_scene_quickjs_layer_registered_asset_path(
    MWXSceneQuickJSDomain *domain,
    JSValueConst value
) {
    if (domain == NULL || !JS_IsObject(value)) return NULL;
    MWXSceneQuickJSAssetHandle *handle = JS_GetOpaque(
        value, domain->asset_handle_class_id
    );
    return handle == NULL ? NULL : handle->path;
}

static JSValue register_asset(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value;
    (void)magic;
    MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_bound_handle_owner(context, opaque, true);
    if (owner == NULL || owner->domain == NULL ||
        owner->domain->module_owner != owner ||
        owner->domain->callback_active || argc < 1 || argc > 2 ||
        !JS_IsString(argv[0])) {
        return JS_ThrowTypeError(
            context, "registerAsset is only available during module evaluation"
        );
    }
    if (argc == 2 && JS_ToBool(context, argv[1]) < 0) return JS_EXCEPTION;
    size_t length = 0;
    const char *path = JS_ToCStringLen(context, &length, argv[0]);
    if (!mwx_scene_quickjs_layer_valid_asset_path(path, length, MWX_SCENE_QUICKJS_MAX_LAYER_ASSET_PATH)) {
        if (path != NULL) JS_FreeCString(context, path);
        return JS_ThrowTypeError(context, "registerAsset path is invalid");
    }
    JSValue result = mwx_scene_quickjs_layer_make_asset_handle(context, owner->domain, path, length);
    JS_FreeCString(context, path);
    return result;
}

bool mwx_scene_quickjs_install_asset_engine(
    MWXSceneQuickJSOwner *owner,
    JSValue engine
) {
    if (owner == NULL || owner->domain == NULL ||
        !JS_IsObject(engine)) return false;
    JSValue function = mwx_scene_quickjs_owner_bound_closure(
        owner, register_asset, "registerAsset", 2, 0
    );
    return !JS_IsException(function) && JS_DefinePropertyValueStr(
        owner->domain->context, engine, "registerAsset", function,
        JS_PROP_ENUMERABLE
    ) >= 0;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_set_asset_path_normalizer(
    MWXSceneQuickJSDomain *domain, MWXSceneQuickJSAssetPathNormalizer normalizer
) {
    if (domain == NULL || domain->context == NULL || normalizer == NULL ||
        domain->asset_path_normalizer != NULL || domain->next_owner_identity != 0 ||
        domain->callback_epoch != 0 || domain->callback_active ||
        domain->frame_input_active || domain->dynamic_image_catalog_configured)
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    domain->asset_path_normalizer = normalizer;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_add_dynamic_image_alias(
    MWXSceneQuickJSOwner *owner,
    const char *authored_path, size_t authored_path_length,
    const char *model_path, size_t model_path_length,
    char *diagnostic, size_t diagnostic_capacity
) {
    if (owner == NULL || owner->domain == NULL || owner->initialized ||
        owner->initialization_pending || owner->domain->callback_active ||
        owner->domain->asset_path_normalizer == NULL ||
        owner->dynamic_image_alias_count >= MWX_SCENE_QUICKJS_MAX_LAYERS ||
        // Internal keys may expand in UTF-8 when the original host lowercases.
        !mwx_scene_quickjs_layer_valid_asset_path(authored_path, authored_path_length, SIZE_MAX - 1) ||
        !mwx_scene_quickjs_layer_valid_asset_path(model_path, model_path_length, MWX_SCENE_QUICKJS_MAX_LAYER_ASSET_PATH))
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    char *authored = owner->domain->asset_path_normalizer(authored_path, authored_path_length);
    if (authored == NULL) return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    for (uint32_t i = 0; i < owner->dynamic_image_alias_count; ++i)
        if (strcmp(owner->dynamic_image_aliases[i].authored_path, authored) == 0) {
            free(authored);
            return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
        }
    char *model = malloc(model_path_length + 1);
    if (model == NULL) {
        free(authored);
        return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    }
    memcpy(model, model_path, model_path_length); model[model_path_length] = '\0';
    MWXSceneQuickJSDynamicImageAliasRecord *aliases = realloc(owner->dynamic_image_aliases,
        (owner->dynamic_image_alias_count + 1) * sizeof(*aliases));
    if (aliases == NULL) {
        free(authored); free(model);
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "dynamic image alias allocation failed");
        return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    }
    owner->dynamic_image_aliases = aliases;
    aliases[owner->dynamic_image_alias_count++] = (MWXSceneQuickJSDynamicImageAliasRecord){authored, model};
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_domain_configure_dynamic_image_catalog(
    MWXSceneQuickJSDomain *domain, uint32_t count,
    const MWXSceneQuickJSDynamicImageDescriptor *descriptors,
    char *diagnostic, size_t diagnostic_capacity
) {
    if (domain == NULL || domain->context == NULL || domain->callback_epoch != 0 ||
        domain->callback_active || domain->frame_input_active ||
        domain->dynamic_image_catalog_configured || domain->asset_path_normalizer == NULL ||
        count > MWX_SCENE_QUICKJS_MAX_LAYERS ||
        (count != 0 && descriptors == NULL))
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    MWXSceneQuickJSDynamicImageRecord *records = count == 0 ? NULL : calloc(count, sizeof(*records));
    if (count != 0 && records == NULL) return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    MWXSceneQuickJSResult result = MWX_SCENE_QUICKJS_OK;
    for (uint32_t index = 0; index < count; ++index) {
        const MWXSceneQuickJSDynamicImageDescriptor *input = &descriptors[index];
        if (!mwx_scene_quickjs_layer_valid_asset_path(input->model_path, input->model_path_length, MWX_SCENE_QUICKJS_MAX_LAYER_ASSET_PATH) || input->autosize > 1 || input->resource_kind > MWX_SCENE_QUICKJS_PREPARED_LAYER_COMPOSITION ||
            (input->resource_kind == MWX_SCENE_QUICKJS_PREPARED_LAYER_COMPOSITION && input->autosize != 0) ||
            !(input->natural_size[0] > 0 && input->natural_size[1] > 0 &&
              input->natural_size[0] <= FLT_MAX && input->natural_size[1] <= FLT_MAX)) {
            result = MWX_SCENE_QUICKJS_INVALID_ARGUMENT; break;
        }
        records[index].identity_key = domain->asset_path_normalizer(input->model_path, input->model_path_length);
        if (records[index].identity_key == NULL) { result = MWX_SCENE_QUICKJS_MEMORY_EXCEEDED; break; }
        for (uint32_t previous = 0; previous < index; ++previous)
            if (strcmp(records[previous].identity_key, records[index].identity_key) == 0)
                result = MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
        if (result != MWX_SCENE_QUICKJS_OK) break;
        records[index].model_path = malloc(input->model_path_length + 1);
        if (records[index].model_path == NULL) { result = MWX_SCENE_QUICKJS_MEMORY_EXCEEDED; break; }
        memcpy(records[index].model_path, input->model_path, input->model_path_length);
        records[index].model_path[input->model_path_length] = '\0';
        memcpy(records[index].natural_size, input->natural_size, sizeof(input->natural_size));
        records[index].autosize = input->autosize != 0;
        records[index].resource_kind = (MWXSceneQuickJSPreparedLayerKind)input->resource_kind;
    }
    if (result != MWX_SCENE_QUICKJS_OK) {
        for (uint32_t index = 0; index < count; ++index) {
            free(records[index].model_path);
            free(records[index].identity_key);
        }
        free(records);
        mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity,
                                          "invalid prepared resource layer catalog");
        return result;
    }
    domain->dynamic_image_resources = records;
    domain->dynamic_image_resource_count = count;
    domain->dynamic_image_catalog_configured = true;
    return MWX_SCENE_QUICKJS_OK;
}
