#include "SceneQuickJSInternal.h"

static MWXSceneQuickJSOwner *executing_owner(MWXSceneQuickJSDomain *domain) {
    if (domain == NULL) return NULL;
    if (domain->callback_active) return domain->active_owner;
    return domain->module_owner;
}

static void clear_rejection(
    MWXSceneQuickJSOwner *owner,
    MWXSceneQuickJSRejectionRecord *record
) {
    if (owner == NULL || record == NULL || !record->active) return;
    JS_FreeValue(owner->domain->context, record->promise);
    JS_FreeValue(owner->domain->context, record->reason);
    record->promise = JS_UNDEFINED;
    record->reason = JS_UNDEFINED;
    record->active = false;
}

static void clear_rejections(MWXSceneQuickJSOwner *owner) {
    if (owner == NULL) return;
    for (
        size_t index = 0;
        index < MWX_SCENE_QUICKJS_MAX_UNHANDLED_REJECTIONS;
        ++index
    ) {
        clear_rejection(owner, &owner->rejections[index]);
    }
    owner->rejection_overflow = false;
}

static void track_promise_rejection(
    JSContext *context,
    JSValueConst promise,
    JSValueConst reason,
    bool is_handled,
    void *opaque
) {
    MWXSceneQuickJSDomain *domain = opaque;
    MWXSceneQuickJSOwner *owner = executing_owner(domain);
    if (owner == NULL || owner->disabled) return;
    MWXSceneQuickJSRejectionRecord *available = NULL;
    for (
        size_t index = 0;
        index < MWX_SCENE_QUICKJS_MAX_UNHANDLED_REJECTIONS;
        ++index
    ) {
        MWXSceneQuickJSRejectionRecord *record = &owner->rejections[index];
        if (record->active &&
            JS_IsStrictEqual(context, record->promise, promise)) {
            if (is_handled) clear_rejection(owner, record);
            return;
        }
        if (!record->active && available == NULL) available = record;
    }
    if (is_handled) return;
    if (available == NULL) {
        owner->rejection_overflow = true;
        return;
    }
    available->promise = JS_DupValue(context, promise);
    available->reason = JS_DupValue(context, reason);
    available->active = true;
}

void mwx_scene_quickjs_install_job_host(MWXSceneQuickJSDomain *domain) {
    if (domain == NULL || domain->runtime == NULL) return;
    JS_SetHostPromiseRejectionTracker(
        domain->runtime, track_promise_rejection, domain
    );
}

void mwx_scene_quickjs_discard_jobs(MWXSceneQuickJSOwner *owner) {
    if (owner == NULL || owner->domain == NULL) return;
    JS_DiscardPendingJobs(owner->domain->runtime);
    clear_rejections(owner);
}

bool mwx_scene_quickjs_owner_has_job_residue(MWXSceneQuickJSOwner *owner) {
    if (owner == NULL || owner->domain == NULL) return false;
    if (JS_IsJobPending(owner->domain->runtime) || owner->rejection_overflow) {
        return true;
    }
    for (
        size_t index = 0;
        index < MWX_SCENE_QUICKJS_MAX_UNHANDLED_REJECTIONS;
        ++index
    ) {
        if (owner->rejections[index].active) return true;
    }
    return false;
}

MWXSceneQuickJSResult mwx_scene_quickjs_drain_jobs(
    MWXSceneQuickJSOwner *owner,
    char *diagnostic,
    size_t diagnostic_capacity
) {
    if (owner == NULL || owner->domain == NULL ||
        !owner->domain->callback_active ||
        owner->domain->active_owner != owner) {
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    size_t executed = 0;
    while (JS_IsJobPending(owner->domain->runtime)) {
        if (executed >= MWX_SCENE_QUICKJS_MAX_JOBS_PER_CALLBACK) {
            mwx_scene_quickjs_discard_jobs(owner);
            mwx_scene_quickjs_write_diagnostic(
                diagnostic,
                diagnostic_capacity,
                "SceneScript pending job budget exceeded"
            );
            return MWX_SCENE_QUICKJS_BUDGET_EXCEEDED;
        }
        if (JS_GetPendingJobContext(owner->domain->runtime) !=
            owner->domain->context) {
            mwx_scene_quickjs_discard_jobs(owner);
            mwx_scene_quickjs_write_diagnostic(
                diagnostic,
                diagnostic_capacity,
                "SceneScript pending job context mismatch"
            );
            return MWX_SCENE_QUICKJS_EXCEPTION;
        }
        JSContext *job_context = NULL;
        int result = JS_ExecutePendingJob(
            owner->domain->runtime, &job_context
        );
        executed += 1;
        if (result < 0) {
            MWXSceneQuickJSResult failure = mwx_scene_quickjs_exception_result(
                owner->domain, diagnostic, diagnostic_capacity
            );
            mwx_scene_quickjs_discard_jobs(owner);
            return failure;
        }
        if (job_context != owner->domain->context) {
            mwx_scene_quickjs_discard_jobs(owner);
            mwx_scene_quickjs_write_diagnostic(
                diagnostic,
                diagnostic_capacity,
                "SceneScript pending job context changed"
            );
            return MWX_SCENE_QUICKJS_EXCEPTION;
        }
    }
    if (owner->rejection_overflow) {
        clear_rejections(owner);
        mwx_scene_quickjs_write_diagnostic(
            diagnostic,
            diagnostic_capacity,
            "SceneScript unhandled rejection budget exceeded"
        );
        return MWX_SCENE_QUICKJS_BUDGET_EXCEEDED;
    }
    for (
        size_t index = 0;
        index < MWX_SCENE_QUICKJS_MAX_UNHANDLED_REJECTIONS;
        ++index
    ) {
        if (owner->rejections[index].active) {
            clear_rejections(owner);
            mwx_scene_quickjs_write_diagnostic(
                diagnostic,
                diagnostic_capacity,
                "SceneScript unhandled promise rejection"
            );
            return MWX_SCENE_QUICKJS_EXCEPTION;
        }
    }
    return MWX_SCENE_QUICKJS_OK;
}

void mwx_scene_quickjs_destroy_job_host(MWXSceneQuickJSOwner *owner) {
    if (owner == NULL) return;
    clear_rejections(owner);
}
