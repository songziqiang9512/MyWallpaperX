#ifndef MWX_SCENE_QUICKJS_MODULE_HOST_H
#define MWX_SCENE_QUICKJS_MODULE_HOST_H

#include "QuickJSNG/quickjs.h"

JSModuleDef *mwx_scene_quickjs_load_allowlisted_module(
    JSContext *context,
    const char *module_name,
    void *opaque
);

#endif
