#include "SceneQuickJSModuleHost.h"

#include <math.h>
#include <stdbool.h>
#include <string.h>

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

static JSValue wemath_mix(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv
) {
    (void)this_value;
    if (argc != 3) {
        return JS_ThrowTypeError(context, "WEMath.mix expects three numbers");
    }
    double start = 0;
    double end = 0;
    double amount = 0;
    if (JS_ToFloat64(context, &start, argv[0]) < 0 ||
        JS_ToFloat64(context, &end, argv[1]) < 0 ||
        JS_ToFloat64(context, &amount, argv[2]) < 0 ||
        !isfinite(start) || !isfinite(end) || !isfinite(amount)) {
        return JS_ThrowTypeError(context, "WEMath.mix arguments are invalid");
    }
    const double result = start + ((end - start) * amount);
    if (!isfinite(result)) {
        return JS_ThrowRangeError(context, "WEMath.mix result is not finite");
    }
    return JS_NewFloat64(context, result);
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
    if (JS_SetModuleExport(context, module, "smoothStep", smooth_step) < 0) {
        return -1;
    }
    JSValue mix = JS_NewCFunction(context, wemath_mix, "mix", 3);
    if (JS_IsException(mix)) {
        return -1;
    }
    return JS_SetModuleExport(context, module, "mix", mix);
}

static bool wecolor_read_vec3(
    JSContext *context,
    JSValueConst value,
    double output[3]
) {
    if (!JS_IsObject(value)) {
        return false;
    }
    static const char *names[] = {"x", "y", "z"};
    for (size_t index = 0; index < 3; ++index) {
        JSValue component = JS_GetPropertyStr(context, value, names[index]);
        const int converted = JS_ToFloat64(context, &output[index], component);
        JS_FreeValue(context, component);
        if (converted < 0 || !isfinite(output[index])) {
            return false;
        }
    }
    return true;
}

static JSValue wecolor_new_vec3(
    JSContext *context,
    double x,
    double y,
    double z
) {
    JSValue global = JS_GetGlobalObject(context);
    JSValue constructor = JS_GetPropertyStr(context, global, "Vec3");
    JS_FreeValue(context, global);
    if (!JS_IsFunction(context, constructor)) {
        JS_FreeValue(context, constructor);
        return JS_ThrowInternalError(context, "WEColor Vec3 host is unavailable");
    }
    JSValue arguments[3] = {
        JS_NewFloat64(context, x),
        JS_NewFloat64(context, y),
        JS_NewFloat64(context, z),
    };
    JSValue result = JS_CallConstructor(context, constructor, 3, arguments);
    for (size_t index = 0; index < 3; ++index) {
        JS_FreeValue(context, arguments[index]);
    }
    JS_FreeValue(context, constructor);
    return result;
}

static JSValue wecolor_hsv_to_rgb(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv
) {
    (void)this_value;
    double hsv[3] = {0};
    if (argc != 1 || !wecolor_read_vec3(context, argv[0], hsv) ||
        hsv[1] < 0 || hsv[1] > 1 || hsv[2] < 0 || hsv[2] > 1) {
        return JS_ThrowTypeError(
            context,
            "WEColor.hsv2rgb expects a finite normalized HSV Vec3"
        );
    }
    const double hue = hsv[0] - floor(hsv[0]);
    const double scaled = hue * 6;
    const int sector = ((int)floor(scaled)) % 6;
    const double fraction = scaled - floor(scaled);
    const double value = hsv[2];
    const double p = value * (1 - hsv[1]);
    const double q = value * (1 - (hsv[1] * fraction));
    const double t = value * (1 - (hsv[1] * (1 - fraction)));
    switch (sector) {
    case 0: return wecolor_new_vec3(context, value, t, p);
    case 1: return wecolor_new_vec3(context, q, value, p);
    case 2: return wecolor_new_vec3(context, p, value, t);
    case 3: return wecolor_new_vec3(context, p, q, value);
    case 4: return wecolor_new_vec3(context, t, p, value);
    default: return wecolor_new_vec3(context, value, p, q);
    }
}

static JSValue wecolor_normalize_color(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv
) {
    (void)this_value;
    double rgb[3] = {0};
    if (argc != 1 || !wecolor_read_vec3(context, argv[0], rgb)) {
        return JS_ThrowTypeError(
            context,
            "WEColor.normalizeColor expects one finite RGB Vec3"
        );
    }
    for (size_t index = 0; index < 3; ++index) {
        if (rgb[index] < 0 || rgb[index] > 255) {
            return JS_ThrowRangeError(
                context,
                "WEColor.normalizeColor components must be in [0, 255]"
            );
        }
    }
    return wecolor_new_vec3(
        context,
        rgb[0] / 255,
        rgb[1] / 255,
        rgb[2] / 255
    );
}

static int initialize_wecolor_module(JSContext *context, JSModuleDef *module) {
    JSValue hsv_to_rgb = JS_NewCFunction(
        context,
        wecolor_hsv_to_rgb,
        "hsv2rgb",
        1
    );
    if (JS_IsException(hsv_to_rgb)) {
        return -1;
    }
    if (JS_SetModuleExport(context, module, "hsv2rgb", hsv_to_rgb) < 0) {
        return -1;
    }
    JSValue normalize_color = JS_NewCFunction(
        context,
        wecolor_normalize_color,
        "normalizeColor",
        1
    );
    if (JS_IsException(normalize_color)) {
        return -1;
    }
    return JS_SetModuleExport(
        context, module, "normalizeColor", normalize_color
    );
}

JSModuleDef *mwx_scene_quickjs_load_allowlisted_module(
    JSContext *context,
    const char *module_name,
    void *opaque
) {
    (void)opaque;
    if (module_name == NULL) {
        JS_ThrowReferenceError(
            context,
            "SceneScript module is not allowlisted: <null>"
        );
        return NULL;
    }
    JSModuleInitFunc *initializer = NULL;
    const char *exports[3] = {NULL, NULL, NULL};
    if (strcmp(module_name, "WEMath") == 0) {
        initializer = initialize_wemath_module;
        exports[0] = "smoothStep";
        exports[1] = "mix";
    } else if (strcmp(module_name, "WEColor") == 0) {
        initializer = initialize_wecolor_module;
        exports[0] = "hsv2rgb";
        exports[1] = "normalizeColor";
    } else {
        JS_ThrowReferenceError(
            context,
            "SceneScript module is not allowlisted: %s",
            module_name
        );
        return NULL;
    }
    JSModuleDef *module = JS_NewCModule(context, module_name, initializer);
    if (module == NULL) {
        return NULL;
    }
    for (size_t index = 0; index < 3 && exports[index] != NULL; ++index) {
        if (JS_AddModuleExport(context, module, exports[index]) < 0) {
            return NULL;
        }
    }
    return module;
}
