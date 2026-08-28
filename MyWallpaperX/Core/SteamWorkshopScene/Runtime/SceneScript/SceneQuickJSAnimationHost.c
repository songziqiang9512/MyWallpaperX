#include "SceneQuickJSInternal.h"

#include <stdlib.h>

typedef struct MWXSceneQuickJSAnimationHandle {
    MWXSceneQuickJSOwner *owner;
    uint64_t callback_epoch;
    MWXSceneQuickJSAnimationCommand command;
} MWXSceneQuickJSAnimationHandle;

static bool callback_owns_animation(
    const MWXSceneQuickJSAnimationHandle *handle
) {
    return handle != NULL && handle->owner != NULL &&
        handle->owner->domain != NULL &&
        handle->owner->domain->callback_active &&
        handle->owner->domain->active_owner == handle->owner &&
        handle->owner->domain->callback_epoch == handle->callback_epoch;
}

static void free_animation_handle(void *opaque) {
    free(opaque);
}

static JSValue mutate_current_animation(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv,
    int magic,
    void *opaque
) {
    (void)this_value;
    (void)argv;
    (void)magic;
    MWXSceneQuickJSAnimationHandle *handle = opaque;
    if (argc != 0 || !callback_owns_animation(handle)) {
        return JS_ThrowTypeError(context, "animation handle is stale");
    }
    MWXSceneQuickJSOwner *owner = handle->owner;
    if (owner->animation_command_count >= MWX_SCENE_QUICKJS_MAX_ANIMATION_COMMANDS) {
        owner->animation_command_overflow = true;
        return JS_ThrowInternalError(context, "animation command buffer exceeded");
    }
    owner->animation_commands[owner->animation_command_count] = handle->command;
    owner->animation_command_count += 1;
    return JS_UNDEFINED;
}

static bool define_animation_command(
    JSContext *context,
    JSValue animation,
    MWXSceneQuickJSOwner *owner,
    const char *name,
    MWXSceneQuickJSAnimationCommand command
) {
    MWXSceneQuickJSAnimationHandle *handle = calloc(1, sizeof(*handle));
    if (handle == NULL) return false;
    handle->owner = owner;
    handle->callback_epoch = owner->domain->callback_epoch;
    handle->command = command;
    JSValue callback = JS_NewCClosure(
        context, mutate_current_animation, name,
        free_animation_handle, 0, 0, handle
    );
    if (JS_IsException(callback) ||
        JS_DefinePropertyValueStr(
            context, animation, name, callback, JS_PROP_ENUMERABLE
        ) < 0) {
        return false;
    }
    return true;
}

static JSValue get_animation(
    JSContext *context,
    JSValueConst this_value,
    int argc,
    JSValueConst *argv,
    int magic,
    void *opaque
) {
    (void)this_value;
    (void)argv;
    (void)magic;
    MWXSceneQuickJSOwner *owner = opaque;
    if (owner == NULL || owner->domain == NULL ||
        !owner->domain->callback_active || owner->domain->active_owner != owner) {
        return JS_ThrowTypeError(context, "getAnimation host is unavailable");
    }
    if (argc != 0) {
        return JS_ThrowTypeError(context, "named animation lookup is unsupported");
    }
    if (!owner->current_animation_available) {
        return JS_ThrowRangeError(context, "current property animation does not exist");
    }
    JSValue animation = JS_NewObject(context);
    if (JS_IsException(animation)) return animation;
    if (!define_animation_command(
            context, animation, owner, "play", MWX_SCENE_QUICKJS_ANIMATION_PLAY
        ) ||
        !define_animation_command(
            context, animation, owner, "pause", MWX_SCENE_QUICKJS_ANIMATION_PAUSE
        ) ||
        !define_animation_command(
            context, animation, owner, "stop", MWX_SCENE_QUICKJS_ANIMATION_STOP
        )) {
        JS_FreeValue(context, animation);
        return JS_EXCEPTION;
    }
    return animation;
}

bool mwx_scene_quickjs_install_object_handle(MWXSceneQuickJSOwner *owner) {
    if (owner == NULL || owner->domain == NULL) return false;
    JSContext *context = owner->domain->context;
    JSValue object = JS_NewObject(context);
    if (JS_IsException(object)) return false;
    JSValue animation = JS_NewCClosure(
        context, get_animation, "getAnimation", NULL, 0, 0, owner
    );
    if (JS_IsException(animation) ||
        JS_DefinePropertyValueStr(
            context, object, "getAnimation", animation, JS_PROP_ENUMERABLE
        ) < 0) {
        JS_FreeValue(context, object);
        return false;
    }
    owner->object_handle = object;
    return true;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_configure_current_animation(
    MWXSceneQuickJSOwner *owner,
    uint32_t available,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner == NULL || available != 1 || owner->current_animation_available) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid current animation configuration"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    owner->current_animation_available = true;
    return MWX_SCENE_QUICKJS_OK;
}

size_t mwx_scene_quickjs_owner_animation_command_count(
    const MWXSceneQuickJSOwner *owner
) {
    return owner == NULL ? 0 : owner->animation_command_count;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_animation_command_at(
    const MWXSceneQuickJSOwner *owner,
    size_t index,
    MWXSceneQuickJSAnimationCommand *command,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner == NULL || command == NULL || index >= owner->animation_command_count) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid animation command mutation"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    *command = owner->animation_commands[index];
    return MWX_SCENE_QUICKJS_OK;
}
