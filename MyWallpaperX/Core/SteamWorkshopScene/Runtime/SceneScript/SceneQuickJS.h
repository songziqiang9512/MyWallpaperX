#ifndef MWX_SCENE_QUICKJS_H
#define MWX_SCENE_QUICKJS_H

#include <stddef.h>
#include <stdint.h>

typedef struct MWXSceneQuickJSDomain MWXSceneQuickJSDomain;
typedef struct MWXSceneQuickJSOwner MWXSceneQuickJSOwner;

typedef enum MWXSceneQuickJSResult {
    MWX_SCENE_QUICKJS_OK = 0,
    MWX_SCENE_QUICKJS_INVALID_ARGUMENT = 1,
    MWX_SCENE_QUICKJS_COMPILE_ERROR = 2,
    MWX_SCENE_QUICKJS_EXCEPTION = 3,
    MWX_SCENE_QUICKJS_BUDGET_EXCEEDED = 4,
    MWX_SCENE_QUICKJS_MEMORY_EXCEEDED = 5,
    MWX_SCENE_QUICKJS_BAD_RETURN = 6,
    MWX_SCENE_QUICKJS_DISABLED = 7,
    MWX_SCENE_QUICKJS_STALE_OWNER = 8
} MWXSceneQuickJSResult;

MWXSceneQuickJSDomain *mwx_scene_quickjs_domain_create(
    size_t heap_limit,
    size_t stack_limit,
    uint64_t interrupt_budget,
    char *diagnostic,
    size_t diagnostic_capacity
);

void mwx_scene_quickjs_domain_destroy(MWXSceneQuickJSDomain *domain);

void mwx_scene_quickjs_domain_reset_budget(
    MWXSceneQuickJSDomain *domain,
    uint64_t interrupt_budget
);

MWXSceneQuickJSOwner *mwx_scene_quickjs_owner_create(
    MWXSceneQuickJSDomain *domain,
    const char *source,
    size_t source_length,
    uint64_t generation,
    char *diagnostic,
    size_t diagnostic_capacity
);

void mwx_scene_quickjs_owner_destroy(MWXSceneQuickJSOwner *owner);

MWXSceneQuickJSResult mwx_scene_quickjs_owner_update_scalar(
    MWXSceneQuickJSOwner *owner,
    uint64_t expected_generation,
    double input,
    double *output,
    char *diagnostic,
    size_t diagnostic_capacity
);

void mwx_scene_quickjs_owner_invalidate(MWXSceneQuickJSOwner *owner);

#endif
