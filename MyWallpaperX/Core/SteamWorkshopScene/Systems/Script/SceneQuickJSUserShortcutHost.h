#ifndef MWX_SCENE_QUICKJS_USER_SHORTCUT_HOST_H
#define MWX_SCENE_QUICKJS_USER_SHORTCUT_HOST_H

#include "SceneQuickJSHostTypes.h"

/* Synchronous host result: 1=true, 0=false, every other value throws.
 * The host owns gesture/configuration validation and all action budgets. */
typedef int32_t (*MWXSceneQuickJSUserShortcutDispatch)(
    void *opaque, const char *key, size_t key_length
);

/* Temporary cursor-dispatch scope only. The caller clears before returning;
 * no callback/context is retained by a journal or replayed as a mutation. */
void mwx_scene_quickjs_owner_set_user_shortcut_dispatch(
    MWXSceneQuickJSOwner *owner,
    MWXSceneQuickJSUserShortcutDispatch dispatch,
    void *opaque
);

#endif
