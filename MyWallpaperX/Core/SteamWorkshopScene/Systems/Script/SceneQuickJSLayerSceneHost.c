#include "SceneQuickJSInternal.h"

#include <math.h>
#include <float.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

int32_t mwx_scene_quickjs_layer_active_count(MWXSceneQuickJSDomain *domain) {
    int32_t count = 0;
    for (uint32_t index = 0; index < domain->layer_count; ++index)
        if (domain->layers[index].configured && !domain->layers[index].destroyed) count += 1;
    return count;
}

int32_t mwx_scene_quickjs_layer_storage_at_order(MWXSceneQuickJSDomain *domain, int32_t order) {
    for (uint32_t index = 0; index < domain->layer_count; ++index) {
        MWXSceneQuickJSLayerRecord *record = &domain->layers[index];
        if (record->configured && !record->destroyed && record->order_index == order)
            return (int32_t)index;
    }
    return -1;
}

static JSValue get_layer(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)magic;
    MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_bound_handle_owner(context, opaque, false);
    if (!mwx_scene_quickjs_layer_callback_owns(owner) || argc != 1) return JS_ThrowTypeError(context, "getLayer unavailable");
    int32_t storage = -1;
    if (JS_IsString(argv[0])) {
        size_t length = 0; const char *name = JS_ToCStringLen(context, &length, argv[0]);
        if (name == NULL) return JS_EXCEPTION;
        for (uint32_t index = 0; index < owner->domain->layer_count; ++index) {
            MWXSceneQuickJSLayerRecord *record = &owner->domain->layers[index];
            if (record->configured && !record->destroyed && strlen(record->name) == length &&
                memcmp(record->name, name, length) == 0) { storage = (int32_t)index; break; }
        }
        JS_FreeCString(context, name);
    } else {
        double numeric = -1;
        if (JS_ToFloat64(context, &numeric, argv[0]) < 0 || !isfinite(numeric) ||
            floor(numeric) != numeric || numeric < 0 || numeric > INT32_MAX)
            return JS_ThrowRangeError(context, "getLayer index is invalid");
        storage = mwx_scene_quickjs_layer_storage_at_order(owner->domain, (int32_t)numeric);
    }
    if (storage < 0) return JS_NULL;
    return mwx_scene_quickjs_layer_make_layer_handle(context, owner, (uint32_t)storage, true);
}

static JSValue get_initial_layer_config(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_bound_handle_owner(context, opaque, false);
    if (!mwx_scene_quickjs_layer_callback_owns(owner) || argc != 1)
        return JS_ThrowTypeError(context, "getInitialLayerConfig expects one layer");
    JSValue layer = JS_UNDEFINED;
    if (JS_IsString(argv[0]) || JS_IsNumber(argv[0])) {
        if (JS_IsNumber(argv[0])) {
            double index = 0;
            if (JS_ToFloat64(context, &index, argv[0]) < 0) return JS_EXCEPTION;
            if (!isfinite(index) || floor(index) != index || index < 0 || index > INT32_MAX)
                return JS_NULL;
        }
        layer = get_layer(context, this_value, argc, argv, magic, opaque);
        if (JS_IsException(layer)) return layer;
    } else {
        layer = JS_DupValue(context, argv[0]);
    }
    MWXSceneQuickJSLayerRecord *record = mwx_scene_quickjs_layer_resolve_layer_argument(context, owner, layer);
    JS_FreeValue(context, layer);
    if (record == NULL) return JS_NULL;
    if (record->initial_configuration == NULL) {
        if (record->dynamic)
            return JS_ThrowTypeError(context, "dynamic initial configuration is unavailable");
        return JS_NULL;
    }
    JSValue configuration = JS_ReadObject(context, record->initial_configuration,
                                          record->initial_configuration_length, 0);
    if (JS_IsException(configuration)) return configuration;
    JSAtom id = JS_NewAtom(context, "id");
    if (id == JS_ATOM_NULL) { JS_FreeValue(context, configuration); return JS_EXCEPTION; }
    int deleted = JS_DeleteProperty(context, configuration, id, 0);
    JS_FreeAtom(context, id);
    if (deleted < 0) { JS_FreeValue(context, configuration); return JS_EXCEPTION; }
    return configuration;
}

static JSValue get_layer_by_id(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)magic;
    MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_bound_handle_owner(context, opaque, false); double value = 0;
    if (!mwx_scene_quickjs_layer_callback_owns(owner) || argc != 1 || JS_ToFloat64(context, &value, argv[0]) < 0 ||
        !isfinite(value) || floor(value) != value || fabs(value) > 9007199254740991.0)
        return JS_ThrowTypeError(context, "getLayerByID expects one integer id");
    for (uint32_t index = 0; index < owner->domain->layer_count; ++index) {
        MWXSceneQuickJSLayerRecord *record = &owner->domain->layers[index];
        if (record->configured && !record->destroyed && record->layer_id == (int64_t)value)
            return mwx_scene_quickjs_layer_make_layer_handle(context, owner, index, true);
    }
    return JS_NULL;
}

static bool read_optional_string(
    JSContext *context, JSValueConst object, const char *key,
    size_t maximum, char **output
) {
    JSValue value = JS_GetPropertyStr(context, object, key);
    if (JS_IsUndefined(value)) { JS_FreeValue(context, value); *output = calloc(1, 1); return *output != NULL; }
    size_t length = 0; const char *string = JS_ToCStringLen(context, &length, value);
    JS_FreeValue(context, value);
    if (string == NULL || length > maximum || memchr(string, '\0', length) != NULL) {
        if (string != NULL) JS_FreeCString(context, string); return false;
    }
    *output = malloc(length + 1);
    if (*output != NULL) { memcpy(*output, string, length); (*output)[length] = '\0'; }
    JS_FreeCString(context, string); return *output != NULL;
}

// Object text is admitted only by an already prepared catalog identity.
static bool read_optional_text(JSContext *context, MWXSceneQuickJSDomain *domain,
    JSValueConst object, char **output, uint64_t *identity) {
    JSValue value = JS_GetPropertyStr(context, object, "text");
    if (JS_IsObject(value)) {
        *identity = mwx_scene_quickjs_match_text_template(domain, value);
        *output = *identity ? mwx_scene_quickjs_text_template_input(domain, *identity) : calloc(1, 1);
        if (!*identity) *identity = UINT64_MAX;
        JS_FreeValue(context, value);
        return *output != NULL;
    }
    if (JS_IsUndefined(value)) {
        JS_FreeValue(context, value); *output = calloc(1, 1); return *output != NULL;
    }
    size_t length = 0;
    const char *text = JS_ToCStringLen(context, &length, value);
    JS_FreeValue(context, value);
    if (!text || length > MWX_SCENE_QUICKJS_MAX_LAYER_TEXT || memchr(text, 0, length)) {
        if (text) JS_FreeCString(context, text);
        return false;
    }
    *output = malloc(length + 1);
    if (*output) { memcpy(*output, text, length); (*output)[length] = 0; }
    JS_FreeCString(context, text);
    return *output != NULL;
}

static bool text_identity_unchanged(JSContext *context, MWXSceneQuickJSDomain *domain,
    JSValueConst configuration, uint64_t identity) {
    if (JS_IsProxy(configuration)) return false;
    JSPropertyDescriptor property = {.value=JS_UNDEFINED,.getter=JS_UNDEFINED,.setter=JS_UNDEFINED};
    JSAtom key = JS_NewAtom(context, "text");
    int found = JS_GetOwnProperty(context, &property, configuration, key);
    JS_FreeAtom(context, key);
    bool valid = found == 1 && (property.flags & JS_PROP_TMASK) == JS_PROP_NORMAL &&
        mwx_scene_quickjs_text_template_matches_identity(domain, property.value, identity);
    JS_FreeValue(context, property.value); JS_FreeValue(context, property.getter); JS_FreeValue(context, property.setter);
    return valid;
}

static bool read_optional_font(
    JSContext *context,
    MWXSceneQuickJSDomain *domain,
    JSValueConst object,
    char **output
) {
    JSValue value = JS_GetPropertyStr(context, object, "font");
    if (JS_IsUndefined(value)) {
        JS_FreeValue(context, value);
        *output = calloc(1, 1);
        return *output != NULL;
    }
    const char *path = mwx_scene_quickjs_layer_registered_asset_path(domain, value);
    const size_t length = path == NULL ? 0 : strlen(path);
    if (!mwx_scene_quickjs_layer_valid_asset_path(path, length, MWX_SCENE_QUICKJS_MAX_LAYER_ASSET_PATH) ||
        length > MWX_SCENE_QUICKJS_MAX_LAYER_FONT) {
        JS_FreeValue(context, value);
        return false;
    }
    *output = malloc(length + 1);
    if (*output != NULL) memcpy(*output, path, length + 1);
    JS_FreeValue(context, value);
    return *output != NULL;
}

static double optional_number(JSContext *context, JSValueConst object, const char *key, double fallback) {
    JSValue value = JS_GetPropertyStr(context, object, key); double result = fallback;
    if (!JS_IsUndefined(value) && JS_ToFloat64(context, &result, value) < 0) result = NAN;
    JS_FreeValue(context, value); return result;
}

static bool read_optional_bool(
    JSContext *context, JSValueConst object, const char *key,
    bool fallback, bool *output
) {
    JSValue value = JS_GetPropertyStr(context, object, key);
    if (JS_IsUndefined(value)) {
        JS_FreeValue(context, value);
        *output = fallback;
        return true;
    }
    if (!JS_IsBool(value)) {
        JS_FreeValue(context, value);
        return false;
    }
    int result = JS_ToBool(context, value);
    JS_FreeValue(context, value);
    if (result < 0) return false;
    *output = result != 0;
    return true;
}

static bool read_optional_vec3(
    JSContext *context, JSValueConst object, const char *key,
    const double fallback[3], double output[3]
) {
    JSValue value = JS_GetPropertyStr(context, object, key);
    if (JS_IsUndefined(value)) {
        JS_FreeValue(context, value);
        if (output != fallback)
            memcpy(output, fallback, sizeof(double) * 3);
        return true;
    }
    const bool valid = (JS_IsObject(value) || JS_IsString(value)) &&
        mwx_scene_quickjs_read_vector(context, value, output, 3, false);
    JS_FreeValue(context, value);
    return valid;
}

static bool parse_color(const char *text, double color[3]) {
    if (text == NULL ||
        sscanf(text, " %lf %lf %lf ", &color[0], &color[1], &color[2]) != 3)
        return false;
    return isfinite(color[0]) && isfinite(color[1]) && isfinite(color[2]);
}

static bool read_optional_color(
    JSContext *context, JSValueConst object,
    const double fallback[3], double output[3]
) {
    JSValue value = JS_GetPropertyStr(context, object, "color");
    if (JS_IsUndefined(value)) {
        JS_FreeValue(context, value);
        if (output != fallback)
            memcpy(output, fallback, sizeof(double) * 3);
        return true;
    }
    bool valid = false;
    if (JS_IsString(value)) {
        const char *text = JS_ToCString(context, value);
        valid = text != NULL && parse_color(text, output);
        if (text != NULL) JS_FreeCString(context, text);
    } else if (JS_IsObject(value)) {
        valid = mwx_scene_quickjs_layer_read_vec3(context, value, output, NULL);
    }
    JS_FreeValue(context, value);
    return valid;
}

static bool read_optional_asset_path(
    JSContext *context, JSValueConst object, char **output
) {
    JSValue value = JS_GetPropertyStr(context, object, "image");
    if (JS_IsUndefined(value)) {
        JS_FreeValue(context, value);
        *output = calloc(1, 1);
        return *output != NULL;
    }
    if (!JS_IsString(value)) {
        JS_FreeValue(context, value);
        return false;
    }
    size_t length = 0;
    const char *path = JS_ToCStringLen(context, &length, value);
    JS_FreeValue(context, value);
    if (path == NULL || length == 0 ||
        length > MWX_SCENE_QUICKJS_MAX_LAYER_ASSET_PATH ||
        memchr(path, '\0', length) != NULL) {
        if (path != NULL) JS_FreeCString(context, path);
        return false;
    }
    *output = malloc(length + 1);
    if (*output != NULL) {
        memcpy(*output, path, length);
        (*output)[length] = '\0';
    }
    JS_FreeCString(context, path);
    return *output != NULL;
}

static bool read_optional_size(JSContext *context, MWXSceneQuickJSDomain *domain,
                               JSValueConst object, double output[2], bool *available) {
    JSValue value = JS_GetPropertyStr(context, object, "size");
    bool valid = !JS_IsException(value);
    int instance = valid && JS_IsObject(value)
        ? JS_IsInstanceOf(context, value, domain->vec2_constructor) : 0;
    if (instance < 0) valid = false;
    if (valid && JS_IsObject(value) && instance == 0) {
        JSAtom script = JS_NewAtom(context, "script"), user = JS_NewAtom(context, "user");
        valid = script != JS_ATOM_NULL && user != JS_ATOM_NULL &&
            JS_HasProperty(context, value, script) == 0 &&
            JS_HasProperty(context, value, user) == 0;
        JS_FreeAtom(context, script); JS_FreeAtom(context, user);
        if (valid) {
            JSValue wrapped = JS_GetPropertyStr(context, value, "value");
            JS_FreeValue(context, value);
            value = wrapped;
            valid = !JS_IsException(value);
            instance = valid && JS_IsObject(value)
                ? JS_IsInstanceOf(context, value, domain->vec2_constructor) : 0;
            if (instance < 0) valid = false;
        }
    }
    *available = valid && (JS_IsString(value) || JS_IsNumber(value) ||
        (JS_IsObject(value) && instance == 1));
    if (*available)
        valid = mwx_scene_quickjs_read_vector(context, value, output, 2, JS_IsNumber(value));
    JS_FreeValue(context, value);
    return valid;
}

static bool read_optional_perspective(JSContext *context, JSValueConst object,
                                      uint32_t *output) {
    JSValue value = JS_GetPropertyStr(context, object, "perspective");
    bool valid = !JS_IsException(value);
    if (!JS_IsUndefined(value))
        *output = JS_IsBool(value) && JS_ToBool(context, value) != 0;
    JS_FreeValue(context, value);
    return valid;
}

static JSValue create_layer(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)magic;
    MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_bound_handle_owner(context, opaque, false);
    if (!mwx_scene_quickjs_layer_callback_owns(owner))
        return JS_ThrowTypeError(context, "createLayer expects one configuration or asset path");
    MWXSceneQuickJSDomain *domain = owner->domain;
    if (owner->value_only)
        return JS_ThrowTypeError(context, "Boolean value owner scene handle is read-only");
    if (argc != 1 ||
        (!JS_IsObject(argv[0]) && !JS_IsString(argv[0])))
        return JS_ThrowTypeError(
            context, "createLayer expects one configuration or asset path"
        );
    size_t scene_dynamic = 0;
    for (uint32_t i = 0; i < domain->layer_count; ++i)
        if (domain->layers[i].dynamic && !domain->layers[i].destroyed) {
            scene_dynamic += 1;
        }
    // Creation is bounded by the shared scene capacity; the callback journal
    // independently limits the number of distinct records it can publish.
    if (scene_dynamic >= MWX_SCENE_QUICKJS_MAX_SCENE_DYNAMIC_LAYERS ||
        domain->layer_count >= MWX_SCENE_QUICKJS_MAX_LAYERS ||
        owner->layer_mutation_count >= MWX_SCENE_QUICKJS_MAX_LAYER_MUTATIONS)
        return JS_NULL;
    char *text = NULL, *font = NULL, *name = NULL;
    uint64_t text_template_identity = 0;
    char *asset_path = NULL;
    double point_size = 32, alpha = 1;
    double origin[3] = {0, 0, 0};
    double scale[3] = {1, 1, 1};
    double angles[3] = {0, 0, 0};
    double color[3] = {1, 1, 1};
    double size[2] = {0, 0};
    bool size_available = false;
    uint32_t perspective = 2;
    bool visible = true;
    bool solid = true;
    const char *registered_asset = mwx_scene_quickjs_layer_registered_asset_path(domain, argv[0]);
    if (JS_IsString(argv[0]) || registered_asset != NULL) {
        size_t length = 0;
        const char *path = registered_asset;
        if (path != NULL) {
            length = strlen(path);
        } else {
            path = JS_ToCStringLen(context, &length, argv[0]);
        }
        if (!mwx_scene_quickjs_layer_valid_asset_path(path, length, MWX_SCENE_QUICKJS_MAX_LAYER_ASSET_PATH)) {
            if (registered_asset == NULL && path != NULL)
                JS_FreeCString(context, path);
            return JS_ThrowTypeError(context, "dynamic layer asset path is invalid");
        }
        asset_path = malloc(length + 1);
        text = calloc(1, 1); font = calloc(1, 1); name = calloc(1, 1);
        if (asset_path != NULL) {
            memcpy(asset_path, path, length); asset_path[length] = '\0';
        }
        if (registered_asset == NULL) JS_FreeCString(context, path);
        if (asset_path == NULL || text == NULL || font == NULL || name == NULL) {
            free(asset_path); free(text); free(font); free(name);
            return JS_EXCEPTION;
        }
    } else {
        if (!read_optional_text(context, domain, argv[0], &text, &text_template_identity) ||
            !read_optional_font(context, domain, argv[0], &font) ||
            !read_optional_string(context, argv[0], "name", MWX_SCENE_QUICKJS_MAX_LAYER_NAME, &name) ||
            !read_optional_asset_path(context, argv[0], &asset_path) ||
            !read_optional_vec3(context, argv[0], "origin", origin, origin) ||
            !read_optional_vec3(context, argv[0], "scale", scale, scale) ||
            !read_optional_vec3(context, argv[0], "angles", angles, angles) ||
            !read_optional_color(context, argv[0], color, color) ||
            !read_optional_bool(context, argv[0], "visible", true, &visible) ||
            !read_optional_bool(context, argv[0], "solid", true, &solid) ||
            !read_optional_perspective(context, argv[0], &perspective)) {
            free(text); free(font); free(name); free(asset_path);
            if (JS_HasException(context)) return JS_EXCEPTION;
            return JS_ThrowTypeError(context, "dynamic layer configuration field is invalid");
        }
        if (asset_path[0] != '\0' &&
            !read_optional_size(context, domain, argv[0], size, &size_available)) {
            free(text); free(font); free(name); free(asset_path);
            return JS_HasException(context) ? JS_EXCEPTION : JS_NULL;
        }
        point_size = optional_number(context, argv[0], "pointsize", 32);
        alpha = optional_number(context, argv[0], "alpha", 1);
        if (!isfinite(point_size) || point_size < 1 || point_size > 1024 ||
            !isfinite(alpha) || alpha < 0 || alpha > 1 ||
            color[0] < 0 || color[0] > 1 || color[1] < 0 || color[1] > 1 ||
            color[2] < 0 || color[2] > 1) {
            free(text); free(font); free(name); free(asset_path);
            return JS_ThrowRangeError(context, "dynamic layer configuration is invalid");
        }
    }
    if (asset_path[0] != '\0') {
        // The prepared owner resolves namespaces; the original host identity
        // rule supplies comparison keys. Keep canonical spelling in the record.
        char *identity = domain->asset_path_normalizer == NULL ? NULL :
            domain->asset_path_normalizer(asset_path, strlen(asset_path));
        if (domain->asset_path_normalizer != NULL && identity == NULL) {
            free(text); free(font); free(name); free(asset_path);
            return JS_ThrowOutOfMemory(context);
        }
        for (uint32_t index = 0; index < owner->dynamic_image_alias_count; ++index) {
            const MWXSceneQuickJSDynamicImageAliasRecord *alias = &owner->dynamic_image_aliases[index];
            if (strcmp(alias->authored_path, identity) != 0) continue;
            char *resolved = strdup(alias->model_path);
            if (resolved == NULL) {
                free(identity); free(text); free(font); free(name); free(asset_path);
                return JS_ThrowOutOfMemory(context);
            }
            free(asset_path); asset_path = resolved;
            free(identity);
            identity = domain->asset_path_normalizer(asset_path, strlen(asset_path));
            if (identity == NULL) {
                free(text); free(font); free(name); free(asset_path);
                return JS_ThrowOutOfMemory(context);
            }
            break;
        }
        const MWXSceneQuickJSDynamicImageRecord *resource = NULL;
        for (uint32_t index = 0; index < domain->dynamic_image_resource_count; ++index)
            if (strcmp(domain->dynamic_image_resources[index].identity_key, identity) == 0) {
                resource = &domain->dynamic_image_resources[index]; break;
            }
        free(identity);
        if (domain->dynamic_image_catalog_configured && resource == NULL) {
            free(text); free(font); free(name); free(asset_path);
            return JS_NULL;
        }
        if (resource != NULL && resource->resource_kind != MWX_SCENE_QUICKJS_PREPARED_LAYER_IMAGE && JS_IsObject(argv[0])) {
            // Special templates supply only prepared empty/default geometry.
            // Presence covers prototypes without invoking unknown values.
            const char *puppet_fields[] = {"animations", "puppetAnimationLayers", "effects"};
            const char *composition_fields[] = {"animations", "puppetAnimationLayers", "effects",
                "copybackground", "config", "parent", "children", "dependencies"};
            bool composition = resource->resource_kind == MWX_SCENE_QUICKJS_PREPARED_LAYER_COMPOSITION;
            const char **unsupported_fields = composition ? composition_fields : puppet_fields;
            size_t field_count = composition ? sizeof(composition_fields) / sizeof(*composition_fields)
                : sizeof(puppet_fields) / sizeof(*puppet_fields);
            for (size_t index = 0; index < field_count; ++index) {
                JSAtom field = JS_NewAtom(context, unsupported_fields[index]);
                int present = field == JS_ATOM_NULL ? -1 : JS_HasProperty(context, argv[0], field);
                if (field != JS_ATOM_NULL) JS_FreeAtom(context, field);
                if (present != 0) {
                    free(text); free(font); free(name); free(asset_path);
                    return present < 0 ? JS_EXCEPTION : JS_NULL;
                }
            }
        }
        if (resource != NULL && strcmp(asset_path, resource->model_path) != 0) {
            char *canonical = strdup(resource->model_path);
            if (canonical == NULL) {
                free(text); free(font); free(name); free(asset_path);
                return JS_ThrowOutOfMemory(context);
            }
            free(asset_path); asset_path = canonical;
        }
        if (resource != NULL && resource->autosize) {
            memcpy(size, resource->natural_size, sizeof(size));
        } else if (!size_available) {
            size[0] = size[1] = 1;
        }
        // Logical signed/degenerate geometry is legal publicly but the current
        // publication/capture/cursor lane cannot consume it. Reject this create
        // before journaling so healthy peers keep their transaction.
        if (!(size[0] > 0 && size[1] > 0 && size[0] <= FLT_MAX && size[1] <= FLT_MAX &&
              (float)size[0] > 0 && (float)size[1] > 0)) {
            free(text); free(font); free(name); free(asset_path);
            return JS_NULL;
        }
        size_available = true;
    }
    for (uint32_t component = 0; component < 3; ++component) {
        angles[component] *= 180.0 / 3.14159265358979323846;
        if (!isfinite(angles[component])) {
            free(text); free(font); free(name); free(asset_path);
            return JS_NULL;
        }
    }
    // All fields that can execute JavaScript have completed before admission.
    if (text_template_identity && (text_template_identity == UINT64_MAX || asset_path[0] != 0 ||
        !text_identity_unchanged(context, domain, argv[0], text_template_identity) ||
        !mwx_scene_quickjs_text_clone_can_begin(owner, text_template_identity))) {
        free(text); free(font); free(name); free(asset_path);
        return JS_NULL;
    }
    // A child cannot introduce a second nested topology/command transaction.
    // Ordinary String create outside this new activation keeps its old path.
    if (domain->text_clone_depth != 0) {
        owner->text_clone_failed = true;
        free(text); free(font); free(name); free(asset_path);
        return JS_NULL;
    }
    if (!mwx_scene_quickjs_layer_ensure_dynamic_layer_transaction(owner)) {
        free(text); free(font); free(name); free(asset_path);
        return JS_ThrowInternalError(context, "dynamic layer transaction unavailable");
    }
    int64_t identity = -1;
    for (;;) {
        bool collision = false;
        for (uint32_t i = 0; i < domain->layer_count; ++i)
            if (domain->layers[i].configured && domain->layers[i].layer_id == identity) collision = true;
        if (!collision) break;
        if (identity <= -9007199254740991LL) {
            free(text); free(font); free(name); free(asset_path);
            return JS_ThrowInternalError(context, "dynamic layer identity exhausted");
        }
        identity -= 1;
    }
    const uint32_t index = domain->layer_count;
    const int32_t insertion_order = mwx_scene_quickjs_layer_active_count(domain);
    if (!mwx_scene_quickjs_layer_journal_dynamic_layer_creation(owner, index)) {
        free(text); free(font); free(name); free(asset_path);
        return JS_ThrowInternalError(
            context, "dynamic layer creation journal exceeded"
        );
    }
    if (!mwx_scene_quickjs_layer_append_dynamic_layer_topology_operation(
            owner, MWX_SCENE_QUICKJS_DYNAMIC_LAYER_CREATE,
            index, insertion_order)) {
        free(text); free(font); free(name); free(asset_path);
        return JS_ThrowInternalError(
            context, "dynamic layer topology operation journal exceeded"
        );
    }
    domain->layer_count += 1;
    MWXSceneQuickJSLayerRecord *record = &domain->layers[index];
    *record = (MWXSceneQuickJSLayerRecord){
        .layer_id = identity, .name = name, .text = text, .font = font,
        .asset_path = asset_path,
        .current_origin = {origin[0], origin[1], origin[2]},
        .scale = {scale[0], scale[1], scale[2]},
        .angles = {angles[0], angles[1], angles[2]},
        .color = {color[0], color[1], color[2]},
        .size = {size[0], size[1]}, .size_available = size_available,
        .alpha = alpha, .point_size = point_size,
        .order_index = insertion_order, .owner_identity = owner->identity,
        .visible = visible, .solid = solid, .perspective = perspective, .dynamic = true, .configured = true,
    };
    if (!mwx_scene_quickjs_layer_mark_dirty(owner, record)) {
        free(record->name);
        free(record->text);
        free(record->font);
        free(record->asset_path);
        *record = (MWXSceneQuickJSLayerRecord){0};
        return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
    }
    if (text_template_identity && !mwx_scene_quickjs_activate_text_clone(owner, index, text_template_identity)) {
        // Birth has occurred: even a caller catch cannot accept this bundle.
        owner->text_clone_failed = true;
        return JS_NULL;
    }
    JSValue handle = mwx_scene_quickjs_layer_make_layer_handle(context, owner, index, true);
    if (JS_IsException(handle)) {
        if (text_template_identity) owner->text_clone_failed = true;
        free(record->name);
        free(record->text);
        free(record->font);
        free(record->asset_path);
        *record = (MWXSceneQuickJSLayerRecord){0};
        if (owner->layer_mutation_count > 0) owner->layer_mutation_count -= 1;
    }
    return handle;
}

static JSValue get_layer_index(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)magic;
    MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_bound_handle_owner(context, opaque, false);
    if (argc != 1) return JS_ThrowTypeError(context, "getLayerIndex expects one layer");
    MWXSceneQuickJSLayerRecord *record = mwx_scene_quickjs_layer_resolve_layer_argument(
        context, owner, argv[0]
    );
    return JS_NewInt32(context, record == NULL ? -1 : record->order_index);
}

static JSValue get_layer_count(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)argc; (void)argv; (void)magic;
    MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_bound_handle_owner(context, opaque, false);
    if (!mwx_scene_quickjs_layer_callback_owns(owner)) return JS_ThrowTypeError(context, "getLayerCount unavailable");
    return JS_NewInt32(context, mwx_scene_quickjs_layer_active_count(owner->domain));
}

static JSValue enumerate_layers(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)argv; (void)magic;
    MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_bound_handle_owner(context, opaque, false);
    if (!mwx_scene_quickjs_layer_callback_owns(owner) || argc != 0)
        return JS_ThrowTypeError(context, "enumerateLayers unavailable");
    const int32_t count = mwx_scene_quickjs_layer_active_count(owner->domain);
    JSValue result = JS_NewArray(context);
    if (JS_IsException(result)) return result;
    for (int32_t order = 0; order < count; ++order) {
        const int32_t storage = mwx_scene_quickjs_layer_storage_at_order(owner->domain, order);
        if (storage < 0) {
            JS_FreeValue(context, result);
            return JS_ThrowInternalError(context, "layer render order is invalid");
        }
        JSValue layer = mwx_scene_quickjs_layer_make_layer_handle(
            context, owner, (uint32_t)storage, true
        );
        if (JS_IsException(layer) || JS_SetPropertyUint32(
                context, result, (uint32_t)order, layer
            ) < 0) {
            JS_FreeValue(context, result);
            return JS_EXCEPTION;
        }
    }
    return result;
}

static JSValue sort_layer(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)magic;
    MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_bound_handle_owner(context, opaque, false); double order_value = 0;
    if (!mwx_scene_quickjs_layer_callback_owns(owner))
        return JS_ThrowTypeError(context, "sortLayer expects a layer and non-negative index");
    if (owner->value_only)
        return JS_ThrowTypeError(context, "Boolean value owner scene handle is read-only");
    if (argc != 2 ||
        JS_ToFloat64(context, &order_value, argv[1]) < 0 || !isfinite(order_value) ||
        floor(order_value) != order_value || order_value < 0 || order_value > INT32_MAX)
        return JS_ThrowTypeError(context, "sortLayer expects a layer and non-negative index");
    MWXSceneQuickJSLayerRecord *target = mwx_scene_quickjs_layer_resolve_layer_argument(
        context, owner, argv[0]
    );
    if (target == NULL)
        return JS_ThrowTypeError(context, "sortLayer target is stale");
    if (target->dynamic && !mwx_scene_quickjs_layer_owns_dynamic_target(owner, target))
        return JS_ThrowTypeError(context, "sortLayer target is not an owned dynamic layer");
    int32_t count = mwx_scene_quickjs_layer_active_count(owner->domain);
    int32_t desired = (int32_t)order_value >= count ? count - 1 : (int32_t)order_value;
    int32_t old = target->order_index;
    if (desired == old) return JS_UNDEFINED;
    const uint32_t target_index =
        (uint32_t)(target - owner->domain->layers);
    // Authored and dynamic sorts share the topology journal: baseline+ops
    // rebuild reproduces the sort across mixed frames, rolls it back when the
    // owning batch is rejected, and keeps the C catalog consistent with the
    // order the dirty record reports to Swift.
    if (!mwx_scene_quickjs_layer_append_dynamic_layer_topology_operation(
            owner, MWX_SCENE_QUICKJS_DYNAMIC_LAYER_SORT,
            target_index, desired))
        return JS_ThrowInternalError(
            context, "dynamic layer topology operation journal exceeded"
        );
    if (!mwx_scene_quickjs_layer_mark_dirty(owner, target)) {
        mwx_scene_quickjs_layer_discard_last_dynamic_layer_topology_operation(owner);
        return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
    }
    for (uint32_t i = 0; i < owner->domain->layer_count; ++i) {
        MWXSceneQuickJSLayerRecord *record = &owner->domain->layers[i];
        if (!record->configured || record->destroyed || record == target) continue;
        if (desired < old && record->order_index >= desired && record->order_index < old)
            record->order_index += 1;
        else if (desired > old && record->order_index > old && record->order_index <= desired)
            record->order_index -= 1;
    }
    target->order_index = desired;
    return JS_NewBool(context, true);
}

static JSValue destroy_layer(
    JSContext *context, JSValueConst this_value, int argc,
    JSValueConst *argv, int magic, void *opaque
) {
    (void)this_value; (void)magic;
    MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_bound_handle_owner(context, opaque, false);
    if (!mwx_scene_quickjs_layer_callback_owns(owner))
        return JS_ThrowTypeError(context, "destroyLayer unavailable");
    if (owner->value_only)
        return JS_ThrowTypeError(context, "Boolean value owner scene handle is read-only");
    MWXSceneQuickJSLayerRecord *record = NULL;
    if (argc == 1 && JS_IsString(argv[0])) {
        size_t length = 0;
        const char *name = JS_ToCStringLen(context, &length, argv[0]);
        if (name == NULL) return JS_EXCEPTION;
        for (uint32_t index = 0; index < owner->domain->layer_count; ++index) {
            MWXSceneQuickJSLayerRecord *candidate =
                &owner->domain->layers[index];
            if (candidate->configured && !candidate->destroyed &&
                candidate->name != NULL && strlen(candidate->name) == length &&
                memcmp(candidate->name, name, length) == 0) {
                record = candidate;
                break;
            }
        }
        JS_FreeCString(context, name);
    } else if (argc == 1 && JS_IsNumber(argv[0])) {
        double numeric = -1;
        if (JS_ToFloat64(context, &numeric, argv[0]) < 0 || !isfinite(numeric) ||
            floor(numeric) != numeric || numeric < 0 || numeric > INT32_MAX)
            return JS_ThrowRangeError(context, "destroyLayer index is invalid");
        const int32_t index = mwx_scene_quickjs_layer_storage_at_order(owner->domain, (int32_t)numeric);
        if (index >= 0) record = &owner->domain->layers[index];
    } else if (argc == 1) {
        record = mwx_scene_quickjs_layer_resolve_layer_argument(context, owner, argv[0]);
    }
    if (record == NULL)
        return JS_ThrowTypeError(context, "destroyLayer target is stale");
    const uint32_t record_index =
        (uint32_t)(record - owner->domain->layers);
    if (!record->dynamic) {
        // Authored removal is deferred through the existing owner journal.
        // Swift validates the prepared leaf and retires its script cohorts
        // only after the complete owner bundle is accepted.
        MWXSceneQuickJSAuthoredLayerMutationRecord *mutation =
            mwx_scene_quickjs_stage_authored_mutation(owner, record_index);
        if (mutation == NULL)
            return JS_ThrowInternalError(
                context, "layer mutation buffer exceeded"
            );
        mutation->destroyed = true;
        mutation->fields = 0;
        return JS_NewBool(context, true);
    }
    if (record->owner_identity != owner->identity)
        return JS_ThrowTypeError(context, "destroyLayer target is stale");
    if (!mwx_scene_quickjs_layer_append_dynamic_layer_topology_operation(
            owner, MWX_SCENE_QUICKJS_DYNAMIC_LAYER_DESTROY,
            record_index, -1))
        return JS_ThrowInternalError(
            context, "dynamic layer topology operation journal exceeded"
        );
    if (!mwx_scene_quickjs_layer_mark_dirty(owner, record)) {
        mwx_scene_quickjs_layer_discard_last_dynamic_layer_topology_operation(owner);
        return JS_ThrowInternalError(context, "layer mutation buffer exceeded");
    }
    int32_t removed = record->order_index;
    record->destroyed = true;
    for (uint32_t j = 0; j < owner->domain->layer_count; ++j)
        if (owner->domain->layers[j].configured &&
            !owner->domain->layers[j].destroyed &&
            owner->domain->layers[j].order_index > removed)
            owner->domain->layers[j].order_index -= 1;
    return JS_NewBool(context, true);
}

bool mwx_scene_quickjs_install_scene_layer_handle(MWXSceneQuickJSOwner *owner) {
    JSContext *context = owner->domain->context;
    JSValue scene = JS_NewObject(context);
    if (JS_IsException(scene)) return false;
    struct { const char *name; JSCClosure *function; int argc; } functions[] = {
        {"getLayer", get_layer, 1}, {"getLayerByID", get_layer_by_id, 1},
        {"getLayerCount", get_layer_count, 0},
        {"getInitialLayerConfig", get_initial_layer_config, 1},
        {"enumerateLayers", enumerate_layers, 0}, {"createLayer", create_layer, 1},
        {"destroyLayer", destroy_layer, 1}, {"sortLayer", sort_layer, 2},
        {"getLayerIndex", get_layer_index, 1},
    };
    for (size_t index = 0; index < sizeof(functions) / sizeof(functions[0]); ++index) {
        JSValue function;
        function = mwx_scene_quickjs_owner_bound_closure(owner, functions[index].function,
                                  functions[index].name, functions[index].argc, 0);
        if (JS_IsException(function) || JS_DefinePropertyValueStr(
                context, scene, functions[index].name, function, JS_PROP_ENUMERABLE
            ) < 0) { JS_FreeValue(context, scene); return false; }
    }
    owner->scene_handle = scene;
    return true;
}
