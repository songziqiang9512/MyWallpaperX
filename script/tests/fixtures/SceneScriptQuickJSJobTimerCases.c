#include "SceneScriptQuickJSFixture.h"
#include "SceneQuickJSInternal.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

static MWXSceneQuickJSDomain *timer_domain(MWXSceneScriptQuickJSFixture *fixture) {
    MWXSceneQuickJSDomain *domain = mwx_scene_quickjs_domain_create(
        2 * 1024 * 1024, 512 * 1024, 100000,
        fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(domain != NULL, "timer domain", fixture->diagnostic);
    return domain;
}

static MWXSceneQuickJSOwner *timer_owner(
    MWXSceneScriptQuickJSFixture *fixture, MWXSceneQuickJSDomain *domain,
    const char *source
) {
    MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_owner_create(
        domain, source, strlen(source), 71, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(owner != NULL, "timer owner", fixture->diagnostic);
    return owner;
}

static const char *shared_timer_source =
    "let fired=0, cancel;"
    "export function init(v){cancel=engine.setTimeout(()=>{fired++;},100);"
    "shared.stop=cancel;return v;}"
    "export function update(v){if(v===2)cancel();return v+fired;}"
    "export function destroy(){shared.cleanupCounts=[timerActiveCount()];"
    "cancel();shared.cleanupCounts.push(timerActiveCount());"
    "const current=engine.setTimeout(()=>{},100);"
    "shared.cleanupCounts.push(timerActiveCount());cancel();"
    "shared.cleanupCounts.push(timerActiveCount());current();"
    "shared.cleanupCounts.push(timerActiveCount());shared.destroyCancelled=true;}";

static JSValue timer_active_count(JSContext *ctx, JSValueConst self,
    int argc, JSValueConst *argv) {
    (void)self; (void)argc; (void)argv;
    MWXSceneQuickJSDomain *domain = JS_GetContextOpaque(ctx);
    return JS_NewUint32(ctx, mwx_scene_quickjs_owner_active_timer_count(domain->active_owner));
}

static void shared_cancel_outcomes(MWXSceneScriptQuickJSFixture *fixture) {
    const char *creators[] = {
        shared_timer_source,
        "let total=0;export function init(v){shared.controls={halt:"
        "engine.setTimeout(function(){total+=1;},25*4)};return v;}"
        "export function update(v){return total+v;}",
        shared_timer_source, shared_timer_source,
    };
    const char *callers[] = {
        "export function update(v){shared.stop();return v;}",
        "export function update(v){const finish=shared.controls.halt;finish();return v;}",
        "export function update(v){const stop=shared.stop;stop();throw new Error('rejected');}",
        "export function update(v){shared.stop();return {};}",
    };
    for (size_t variant = 0; variant < 4; ++variant) {
        MWXSceneQuickJSDomain *domain = timer_domain(fixture);
        if (domain == NULL) return;
        MWXSceneQuickJSOwner *a = timer_owner(fixture, domain, creators[variant]);
        MWXSceneQuickJSOwner *b = timer_owner(fixture, domain, callers[variant]);
        if (a != NULL && b != NULL) {
            fixture->failures += mwx_fixture_update_at(a, 71, 1, 0, 0,
                MWX_SCENE_QUICKJS_OK, 1, "shared timer initialized");
            mwx_scene_quickjs_owner_commit_layer_mutations(a);
            MWXSceneQuickJSResult expected = variant == 2 ? MWX_SCENE_QUICKJS_EXCEPTION :
                variant == 3 ? MWX_SCENE_QUICKJS_BAD_RETURN : MWX_SCENE_QUICKJS_OK;
            fixture->failures += mwx_fixture_update_at(b, 71, 1, 0, 0,
                expected, 1, "shared bare/member cancel caller fate");
            mwx_scene_quickjs_owner_discard_layer_mutations(b);
            fixture->failures += mwx_fixture_check(
                mwx_scene_quickjs_owner_active_timer_count(a) == 0,
                "caller failure/discard does not undo foreign scheduling", "");
            fixture->failures += mwx_fixture_update_at(a, 71, 1, .2, .2,
                MWX_SCENE_QUICKJS_OK, 1, "cancelled work never fires in healthy creator");
            if (variant < 2) fixture->failures += mwx_fixture_update_at(b, 71, 1, 0, .2,
                MWX_SCENE_QUICKJS_OK, 1, "inactive live capability is idempotent");
        }
        mwx_scene_quickjs_owner_destroy(b);
        mwx_scene_quickjs_owner_destroy(a);
        JS_RunGC(domain->runtime);
        mwx_scene_quickjs_domain_destroy(domain);
    }
}

static void shared_cancel_snapshots(MWXSceneScriptQuickJSFixture *fixture) {
    for (int variant = 0; variant < 3; ++variant) {
        MWXSceneQuickJSDomain *domain = timer_domain(fixture);
        if (domain == NULL) return;
        MWXSceneQuickJSOwner *a = timer_owner(fixture, domain, shared_timer_source);
        MWXSceneQuickJSOwner *b = timer_owner(fixture, domain,
            "export function update(v){shared.stop();return v;}");
        if (a != NULL && b != NULL) {
            fixture->failures += mwx_fixture_update_at(a, 71, 1, 0, 0,
                MWX_SCENE_QUICKJS_OK, 1, "snapshot creator initialized");
            mwx_scene_quickjs_owner_commit_layer_mutations(a);
            MWXSceneQuickJSTimerFrameSnapshot *snapshot = mwx_scene_quickjs_owner_timer_snapshot(a);
            fixture->failures += mwx_fixture_check(snapshot != NULL, "timer snapshot retained", "");
            if (variant != 0) fixture->failures += mwx_fixture_update_at(a, 71, 2, 0, 0,
                MWX_SCENE_QUICKJS_OK, 2, "same-owner cancel before restore");
            if (variant != 2) fixture->failures += mwx_fixture_update_at(b, 71, 1, 0, 0,
                MWX_SCENE_QUICKJS_OK, 1, "foreign cancel active or already inactive registration");
            fixture->failures += mwx_fixture_check(
                mwx_scene_quickjs_owner_timer_restore(a, snapshot), "timer restore accepted", "");
            fixture->failures += mwx_fixture_check(
                mwx_scene_quickjs_owner_active_timer_count(a) == (variant == 2 ? 1 : 0),
                "snapshot preserves external cancellation but restores local cancellation", "");
            if (variant == 2) {
                fixture->failures += mwx_fixture_update_at(a, 71, 2, 0, 0,
                    MWX_SCENE_QUICKJS_OK, 2, "same capability can cancel restored registration");
            } else {
                fixture->failures += mwx_fixture_update_at(a, 71, 1, .2, .2,
                    MWX_SCENE_QUICKJS_OK, 1, "external cancel survives creator snapshot and due time");
            }
            mwx_scene_quickjs_owner_timer_snapshot_destroy(snapshot, a);
        }
        mwx_scene_quickjs_owner_destroy(b);
        mwx_scene_quickjs_owner_destroy(a);
        JS_RunGC(domain->runtime);
        mwx_scene_quickjs_domain_destroy(domain);
    }
}

static void shared_cancel_permissions(MWXSceneScriptQuickJSFixture *fixture) {
    MWXSceneQuickJSDomain *domain = timer_domain(fixture);
    if (domain == NULL) return;
    MWXSceneQuickJSOwner *a = timer_owner(fixture, domain, shared_timer_source);
    const char *attempt = "export function update(v){try{shared.stop();return false;}"
        "catch(e){return e instanceof TypeError;}}";
    MWXSceneQuickJSResult created = MWX_SCENE_QUICKJS_OK;
    MWXSceneQuickJSOwner *restricted = mwx_scene_quickjs_owner_create_value_only_with_budget(
        domain, attempt, strlen(attempt), 71, 100000, &created,
        fixture->diagnostic, sizeof(fixture->diagnostic));
    MWXSceneQuickJSOwner *b = timer_owner(fixture, domain,
        "export function update(v){try{shared.stop();return 0;}"
        "catch(e){return e instanceof TypeError?1:2;}}");
    fixture->failures += mwx_fixture_check(restricted != NULL, "value-only cancel observer", fixture->diagnostic);
    if (a != NULL && b != NULL && restricted != NULL) {
        fixture->failures += mwx_fixture_update_at(a, 71, 1, 0, 0,
            MWX_SCENE_QUICKJS_OK, 1, "permissions creator initialized");
        mwx_scene_quickjs_owner_commit_layer_mutations(a);
        fixture->failures += mwx_fixture_update_bool(restricted, 71, 1,
            MWX_SCENE_QUICKJS_OK, 1, "value-only caller cannot acquire scheduling power");
        domain->value_only_guard_active = true;
        fixture->failures += mwx_fixture_update_at(b, 71, 1, 0, 0,
            MWX_SCENE_QUICKJS_OK, 1, "nested value-only guard blocks cancel");
        domain->value_only_guard_active = false;
        JSValue outside = JS_GetPropertyStr(domain->context, domain->shared_value, "stop");
        JSValue result = JS_Call(domain->context, outside, JS_UNDEFINED, 0, NULL);
        fixture->failures += mwx_fixture_check(JS_IsException(result),
            "cancel requires active callback", "");
        JS_FreeValue(domain->context, result);
        JS_FreeValue(domain->context, outside);
        JSValue error = JS_GetException(domain->context);
        JSValue error_name = JS_GetPropertyStr(domain->context, error, "name");
        const char *name = JS_ToCString(domain->context, error_name);
        fixture->failures += mwx_fixture_check(name != NULL && strcmp(name, "TypeError") == 0,
            "outside callback rejects at cancellation capability", name);
        JS_FreeCString(domain->context, name);
        JS_FreeValue(domain->context, error_name);
        JS_FreeValue(domain->context, error);
        fixture->failures += mwx_fixture_check(
            mwx_scene_quickjs_owner_active_timer_count(a) == 1,
            "all rejected permissions preserve creator work", "");
        mwx_scene_quickjs_owner_invalidate(a);
        fixture->failures += mwx_fixture_update_at(b, 71, 1, 0, 0,
            MWX_SCENE_QUICKJS_OK, 1, "disabled creator rejects escaped capability");
    }
    mwx_scene_quickjs_owner_destroy(restricted);
    mwx_scene_quickjs_owner_destroy(b);
    mwx_scene_quickjs_owner_destroy(a);
    JS_RunGC(domain->runtime);
    mwx_scene_quickjs_domain_destroy(domain);
}

static void shared_cancel_retirement(MWXSceneScriptQuickJSFixture *fixture) {
    MWXSceneQuickJSDomain *domain = timer_domain(fixture);
    if (domain == NULL) return;
    JSValue global = JS_GetGlobalObject(domain->context);
    fixture->failures += mwx_fixture_check(JS_SetPropertyStr(domain->context, global,
        "timerActiveCount", JS_NewCFunction(domain->context, timer_active_count,
            "timerActiveCount", 0)) >= 0, "test-only native timer count observer", "");
    JS_FreeValue(domain->context, global);
    MWXSceneQuickJSOwner *a = timer_owner(fixture, domain, shared_timer_source);
    MWXSceneQuickJSOwner *b = timer_owner(fixture, domain,
        "export function update(v){try{shared.stop();return 0;}"
        "catch(e){return e instanceof TypeError?1:2;}}");
    MWXSceneQuickJSOwner *replacement = NULL;
    if (a != NULL && b != NULL) {
        fixture->failures += mwx_fixture_update_at(a, 71, 1, 0, 0,
            MWX_SCENE_QUICKJS_OK, 1, "retirement creator initialized");
        mwx_scene_quickjs_owner_commit_layer_mutations(a);
        MWXSceneQuickJSTimerFrameSnapshot *snapshot = mwx_scene_quickjs_owner_timer_snapshot(a);
        MWXSceneQuickJSFrameInput frame = {.runtime = .01, .frame_time = .01};
        uint32_t invoked = 0;
        MWXSceneQuickJSResult result = mwx_scene_quickjs_owner_teardown(
            a, 71, &frame, "", 0, "{}", 2, &invoked,
            fixture->diagnostic, sizeof(fixture->diagnostic));
        fixture->failures += mwx_fixture_check(result == MWX_SCENE_QUICKJS_OK && invoked == 1,
            "destroy callback old-cap cleanup and current-cap cancellation", fixture->diagnostic);
        JSValue counts = JS_GetPropertyStr(domain->context, domain->shared_value, "cleanupCounts");
        JSValue completed = JS_GetPropertyStr(domain->context, domain->shared_value, "destroyCancelled");
        const char *observed = JS_ToCString(domain->context, counts);
        fixture->failures += mwx_fixture_check(observed != NULL &&
            strcmp(observed, "0,0,1,1,0") == 0 && JS_ToBool(domain->context, completed) == 1,
            "old cleanup capability is no-op and cannot cancel new destroy timer", observed);
        JS_FreeCString(domain->context, observed);
        JS_FreeValue(domain->context, completed);
        JS_FreeValue(domain->context, counts);
        fixture->failures += mwx_fixture_check(mwx_scene_quickjs_owner_timer_restore(a, snapshot) &&
            mwx_scene_quickjs_owner_active_timer_count(a) == 0,
            "retired anchor prevents snapshot resurrection", "");
        mwx_scene_quickjs_owner_timer_snapshot_destroy(snapshot, a);
        fixture->failures += mwx_fixture_update_at(b, 71, 1, 0, 0,
            MWX_SCENE_QUICKJS_OK, 1, "retired creator capability rejects safely");
        mwx_scene_quickjs_owner_destroy(a);
        a = NULL;
        JS_RunGC(domain->runtime);
        replacement = timer_owner(fixture, domain,
            "let fired=0;export function init(v){"
            "shared.fresh=engine.setTimeout(()=>{fired++;},100);return v;}"
            "export function update(v){return v+fired;}");
        fixture->failures += mwx_fixture_update_at(replacement, 71, 1, 0, 0,
            MWX_SCENE_QUICKJS_OK, 1, "replacement owner has fresh timer");
        mwx_scene_quickjs_owner_commit_layer_mutations(replacement);
        fixture->failures += mwx_fixture_update_at(b, 71, 1, 0, 0,
            MWX_SCENE_QUICKJS_OK, 1, "old anchor cannot alias replacement owner");
        fixture->failures += mwx_fixture_update_at(replacement, 71, 1, .2, .2,
            MWX_SCENE_QUICKJS_OK, 2, "replacement timer fires despite stale cancel");
    }
    mwx_scene_quickjs_owner_destroy(replacement);
    mwx_scene_quickjs_owner_destroy(b);
    mwx_scene_quickjs_owner_destroy(a);
    JS_RunGC(domain->runtime);
    mwx_scene_quickjs_domain_destroy(domain);
}

static void timer_allocation_pressure(MWXSceneScriptQuickJSFixture *fixture) {
    size_t anchor_failures = 0, later_failures = 0, successes = 0, preserved = 0;
    /* Prebuild JS arguments and the actual installed host function. Restrict
     * memory only around JS_Call so issuance proves failure reached TimerHost,
     * rather than an unrelated frame-engine allocation. No allocator seam. */
    for (int existing = 0; existing < 2; ++existing) {
        for (size_t headroom = 0; headroom <= 1024; headroom += 8) {
            MWXSceneQuickJSDomain *domain = timer_domain(fixture);
            if (domain == NULL) return;
            MWXSceneQuickJSOwner *owner = timer_owner(fixture, domain,
                "export function update(v){return globalThis.pressureFired||0;}");
            if (owner == NULL) { mwx_scene_quickjs_domain_destroy(domain); return; }
            JSContext *ctx = domain->context;
            JSValue engine = JS_NewObject(ctx);
            fixture->failures += mwx_fixture_check(
                mwx_scene_quickjs_install_timer_engine(owner, engine), "pressure actual timer engine", "");
            JSValue timeout = JS_GetPropertyStr(ctx, engine, "setTimeout");
            const char *body = "(()=>{globalThis.pressureFired=(globalThis.pressureFired||0)+1;})";
            JSValue callback = JS_Eval(ctx, body, strlen(body), "pressure-callback", JS_EVAL_TYPE_GLOBAL);
            JSValue args[2] = {callback, JS_NewInt32(ctx, 100)};
            mwx_scene_quickjs_begin_callback(owner);
            if (existing) {
                JSValue first = JS_Call(ctx, timeout, engine, 2, args);
                fixture->failures += mwx_fixture_check(!JS_IsException(first), "existing timer before pressure", "");
                JS_FreeValue(ctx, first);
            }
            uint64_t before = owner->next_timer_identity;
            JS_RunGC(domain->runtime);
            JSMemoryUsage usage;
            JS_ComputeMemoryUsage(domain->runtime, &usage);
            JS_SetMemoryLimit(domain->runtime, (size_t)usage.malloc_size + headroom);
            JSValue result = JS_Call(ctx, timeout, engine, 2, args);
            bool rejected = JS_IsException(result);
            JS_SetMemoryLimit(domain->runtime, 0);
            bool issued = owner->next_timer_identity == before + 1;
            uint32_t active = mwx_scene_quickjs_owner_active_timer_count(owner);
            fixture->failures += mwx_fixture_check(issued && active == (uint32_t)(existing + !rejected),
                "pressure failure rolls back only new registration", "");
            if (rejected) {
                if (owner->timer_lifetime == NULL) anchor_failures++; else later_failures++;
                JSValue error = JS_GetException(ctx);
                JS_FreeValue(ctx, error);
            } else {
                successes++;
                fixture->failures += mwx_fixture_check(!JS_HasException(ctx),
                    "successful cancellation construction leaves no exception", "");
            }
            JS_FreeValue(ctx, result);
            mwx_scene_quickjs_end_callback(owner);
            JS_FreeValue(ctx, callback);
            JS_FreeValue(ctx, timeout);
            JS_FreeValue(ctx, engine);
            if (rejected && existing) {
                fixture->failures += mwx_fixture_update_at(owner, 71, 0, 0, 0,
                    MWX_SCENE_QUICKJS_OK, 0, "existing timer survives allocation failure");
                mwx_scene_quickjs_owner_commit_layer_mutations(owner);
                fixture->failures += mwx_fixture_update_at(owner, 71, 0, .2, .2,
                    MWX_SCENE_QUICKJS_OK, 1, "existing timer still executes after budget restored");
                preserved++;
            }
            mwx_scene_quickjs_owner_destroy(owner);
            JS_RunGC(domain->runtime);
            mwx_scene_quickjs_domain_destroy(domain);
        }
    }
    fixture->failures += mwx_fixture_check(anchor_failures > 0 && later_failures > 0 &&
        successes > 0 && preserved > 0, "timer allocation pressure reaches host failure and success", "");
    printf("MWX_TIMER_ALLOCATION_PRESSURE {\"anchorFailures\":%zu,\"postAnchorFailures\":%zu,"
        "\"successes\":%zu,\"existingTimerPreserved\":%zu}\n",
        anchor_failures, later_failures, successes, preserved);
}

void mwx_fixture_job_timer_cases(MWXSceneScriptQuickJSFixture *fixture) {
    const char *promise_source =
        "let state=0;"
        "export function init(value){"
        "Promise.resolve().then(()=>{state=4;});return value;}"
        "export function update(value){return value+state;}";
    fixture->promise_owner = mwx_scene_quickjs_owner_create(
        fixture->domain, promise_source, strlen(promise_source),
        37, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->promise_owner != NULL, "promise owner compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_update(
        fixture->promise_owner, 37, 1, MWX_SCENE_QUICKJS_OK, 5,
        "promise job drains before next owner hook"
    );

    const char *promise_mutation_source =
        "export function update(value){"
        "Promise.resolve().then(()=>{"
        "thisLayer.getEffect(0).executeMaterialFunction('asyncMutate');});"
        "return value;}";
    fixture->promise_mutation = mwx_scene_quickjs_owner_create(
        fixture->domain, promise_mutation_source, strlen(promise_mutation_source),
        43, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->promise_mutation != NULL, "promise mutation compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_configure_effects(
        fixture->promise_mutation, 1, 0, "async", "promise mutation catalog"
    );
    fixture->failures += mwx_fixture_update(
        fixture->promise_mutation, 43, 1, MWX_SCENE_QUICKJS_OK, 1,
        "promise mutation callback"
    );
    fixture->failures += mwx_fixture_mutation(
        fixture->promise_mutation, 0, 0, "asyncMutate",
        "promise job retains owner handle"
    );

    const char *event_promise_source =
        "export function cursorClick(){"
        "Promise.resolve().then(()=>{shared.eventJob=9;});}"
        "export function update(value){return value+(shared.eventJob||0);}";
    fixture->event_promise = mwx_scene_quickjs_owner_create(
        fixture->domain, event_promise_source, strlen(event_promise_source),
        44, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->event_promise != NULL, "event promise compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_cursor_event(
        fixture->event_promise, 44, MWX_SCENE_QUICKJS_CURSOR_CLICK,
        MWX_SCENE_QUICKJS_OK, "event promise drains before return"
    );
    fixture->failures += mwx_fixture_update(
        fixture->event_promise, 44, 1, MWX_SCENE_QUICKJS_OK, 10,
        "event promise state is visible"
    );

    const char *handled_rejection_source =
        "let state=0;"
        "export function init(value){"
        "Promise.reject(new Error('handled')).catch(()=>{state=3;});"
        "return value;}"
        "export function update(value){return value+state;}";
    fixture->handled_rejection = mwx_scene_quickjs_owner_create(
        fixture->domain, handled_rejection_source, strlen(handled_rejection_source),
        38, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->handled_rejection != NULL, "handled rejection compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->handled_rejection, 38, 1, MWX_SCENE_QUICKJS_OK, 4,
        "handled rejection remains healthy"
    );

    const char *unhandled_rejection_source =
        "export function update(value){"
        "Promise.reject(new Error('unhandled'));return value;}";
    fixture->unhandled_rejection = mwx_scene_quickjs_owner_create(
        fixture->domain, unhandled_rejection_source, strlen(unhandled_rejection_source),
        39, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->unhandled_rejection != NULL, "unhandled rejection compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->unhandled_rejection, 39, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "unhandled rejection disables owner"
    );

    const char *job_budget_source =
        "export function update(value){"
        "let chain=Promise.resolve();"
        "for(let i=0;i<65;i+=1)chain=chain.then(()=>{});"
        "return value;}";
    fixture->job_budget = mwx_scene_quickjs_owner_create(
        fixture->domain, job_budget_source, strlen(job_budget_source),
        40, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->job_budget != NULL, "job budget compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_update(
        fixture->job_budget, 40, 1, MWX_SCENE_QUICKJS_BUDGET_EXCEEDED, 0,
        "job budget disables owner"
    );
    fixture->failures += mwx_fixture_update(
        fixture->isolated, 2, 3, MWX_SCENE_QUICKJS_OK, 13,
        "job failure preserves peer owner"
    );

    const char *module_job_source =
        "Promise.resolve().then(()=>{});"
        "export function update(value){return value;}";
    MWXSceneQuickJSOwner *module_job = mwx_scene_quickjs_owner_create(
        fixture->domain, module_job_source, strlen(module_job_source),
        41, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        module_job == NULL, "module job rejected and discarded", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update(
        fixture->isolated, 2, 3, MWX_SCENE_QUICKJS_OK, 13,
        "module job rejection preserves peer owner"
    );

    const char *timer_promise_source =
        "let state=0,resolveValue;"
        "export function init(value){"
        "new Promise(resolve=>{resolveValue=resolve;})"
        ".then(next=>{state=next;});"
        "engine.setTimeout(()=>{resolveValue(6);},10);return value;}"
        "export function update(value){return value+state;}";
    fixture->timer_promise = mwx_scene_quickjs_owner_create(
        fixture->domain, timer_promise_source, strlen(timer_promise_source),
        42, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->timer_promise != NULL, "timer promise compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_update_at(
        fixture->timer_promise, 42, 1, 0, 0,
        MWX_SCENE_QUICKJS_OK, 1, "timer promise initialization"
    );
    fixture->failures += mwx_fixture_update_at(
        fixture->timer_promise, 42, 1, 0.01, 0.01,
        MWX_SCENE_QUICKJS_OK, 7, "timer resolves promise before update"
    );

    const char *timer_source =
        "let once=0,ticks=0,cancelInterval;"
        "export function init(value){"
        "engine.setTimeout(()=>{once=5;},100);"
        "cancelInterval=engine.setInterval(()=>{"
        "ticks+=1;if(ticks===2)cancelInterval();},50);"
        "const cancelled=engine.setTimeout(()=>{once=99;},0);"
        "cancelled();return value;}"
        "export function update(value){return value+once+ticks;}";
    fixture->timer_owner = mwx_scene_quickjs_owner_create(
        fixture->domain, timer_source, strlen(timer_source),
        30, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->timer_owner != NULL, "timer owner compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_update_at(
        fixture->timer_owner, 30, 1, 0, 0,
        MWX_SCENE_QUICKJS_OK, 1, "timer initialization"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_active_timer_count(fixture->timer_owner) == 2,
        "cancelled timer removed", ""
    );
    const char *timer_snapshot_source =
        "export function init(value){engine.setTimeout(()=>{},0.1);return value;}"
        "export function update(value){return value;}";
    fixture->timer_snapshot_owner = mwx_scene_quickjs_owner_create(
        fixture->domain, timer_snapshot_source, strlen(timer_snapshot_source),
        37, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->timer_snapshot_owner != NULL, "timer snapshot owner compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update_at(
        fixture->timer_snapshot_owner, 37, 1, 0, 0,
        MWX_SCENE_QUICKJS_OK, 1, "timer snapshot initialization"
    );
    MWXSceneQuickJSTimerFrameSnapshot *timer_snapshot =
        mwx_scene_quickjs_owner_timer_snapshot(fixture->timer_snapshot_owner);
    fixture->failures += mwx_fixture_check(
        timer_snapshot != NULL, "timer frame snapshot allocates", ""
    );
    fixture->failures += mwx_fixture_update_at(
        fixture->timer_snapshot_owner, 37, 1, 0.2, 0.2,
        MWX_SCENE_QUICKJS_OK, 1, "timer snapshot consumes provisional timer"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_active_timer_count(fixture->timer_snapshot_owner) == 0,
        "provisional timer is consumed", ""
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_timer_restore(
            fixture->timer_snapshot_owner, timer_snapshot
        ),
        "timer frame restore succeeds", ""
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_active_timer_count(fixture->timer_snapshot_owner) == 1,
        "dropped frame restores timer", ""
    );
    mwx_scene_quickjs_owner_timer_snapshot_destroy(
        timer_snapshot, fixture->timer_snapshot_owner
    );
    fixture->failures += mwx_fixture_update_at(
        fixture->timer_owner, 30, 1, 0.04, 0.04,
        MWX_SCENE_QUICKJS_OK, 1, "timers wait for delay"
    );
    fixture->failures += mwx_fixture_update_at(
        fixture->timer_owner, 30, 1, 0.02, 0.06,
        MWX_SCENE_QUICKJS_OK, 2, "interval first tick"
    );
    fixture->failures += mwx_fixture_update_at(
        fixture->timer_owner, 30, 1, 0.06, 0.12,
        MWX_SCENE_QUICKJS_OK, 8, "timeout and self-cancel interval"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_active_timer_count(fixture->timer_owner) == 0,
        "timer slots released", ""
    );
    fixture->failures += mwx_fixture_update_at(
        fixture->timer_owner, 30, 1, 0.06, 0.12,
        MWX_SCENE_QUICKJS_OK, 8, "same runtime does not advance timers"
    );

    const char *interval_source =
        "let ticks=0;"
        "export function init(value){"
        "engine.setInterval(()=>{ticks+=1;},10);return value;}"
        "export function update(value){return value+ticks;}";
    fixture->interval_owner = mwx_scene_quickjs_owner_create(
        fixture->domain, interval_source, strlen(interval_source),
        31, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->interval_owner != NULL, "interval owner compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_update_at(
        fixture->interval_owner, 31, 1, 0, 0,
        MWX_SCENE_QUICKJS_OK, 1, "interval initialization"
    );
    fixture->failures += mwx_fixture_update_at(
        fixture->interval_owner, 31, 1, 1, 1,
        MWX_SCENE_QUICKJS_OK, 2, "interval long frame runs once"
    );
    fixture->failures += mwx_fixture_update_at(
        fixture->interval_owner, 31, 1, 1, 2,
        MWX_SCENE_QUICKJS_OK, 3, "interval does not catch up"
    );

    const char *timer_cancel_owner_source =
        "export function init(value){"
        "shared.cancel=engine.setTimeout(()=>{},1000);return value;}"
        "export function update(value){return value;}";
    fixture->timer_cancel_owner = mwx_scene_quickjs_owner_create(
        fixture->domain, timer_cancel_owner_source, strlen(timer_cancel_owner_source),
        35, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->timer_cancel_owner != NULL, "timer cancel owner compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update_at(
        fixture->timer_cancel_owner, 35, 1, 0, 0,
        MWX_SCENE_QUICKJS_OK, 1, "timer cancel owner initialization"
    );
    fixture->timer_cancel_intruder = mwx_scene_quickjs_owner_create(
        fixture->domain,
        "export function update(value){shared.cancel();return value;}",
        strlen("export function update(value){shared.cancel();return value;}"),
        36, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->timer_cancel_intruder != NULL, "timer cancel intruder compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update_at(
        fixture->timer_cancel_intruder, 36, 1, 0, 0,
        MWX_SCENE_QUICKJS_OK, 1, "cross-owner timer cancel accepted"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_active_timer_count(fixture->timer_cancel_owner) == 0,
        "cross-owner cancel stops creator timer", ""
    );

    const char *invalid_timer_source =
        "export function update(value){"
        "engine.setTimeout(()=>{},-1);return value;}";
    fixture->invalid_timer = mwx_scene_quickjs_owner_create(
        fixture->domain, invalid_timer_source, strlen(invalid_timer_source),
        32, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->invalid_timer != NULL, "invalid timer owner compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_update_at(
        fixture->invalid_timer, 32, 1, 0, 0,
        MWX_SCENE_QUICKJS_EXCEPTION, 0, "invalid timer disables owner"
    );

    const char *timer_budget_source =
        "export function update(value){"
        "for(let i=0;i<33;i+=1)engine.setTimeout(()=>{},1000);"
        "return value;}";
    fixture->timer_budget = mwx_scene_quickjs_owner_create(
        fixture->domain, timer_budget_source, strlen(timer_budget_source),
        33, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(fixture->timer_budget != NULL, "timer budget owner compile", fixture->diagnostic);
    fixture->failures += mwx_fixture_update_at(
        fixture->timer_budget, 33, 1, 0, 0,
        MWX_SCENE_QUICKJS_EXCEPTION, 0, "timer budget disables owner"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_active_timer_count(fixture->timer_budget) == 32,
        "timer budget remains bounded", ""
    );

    const char *timer_exception_source =
        "export function init(value){"
        "engine.setTimeout(()=>{throw new Error('timer boom');},0);"
        "return value;}"
        "export function update(value){return value;}";
    fixture->timer_exception = mwx_scene_quickjs_owner_create(
        fixture->domain, timer_exception_source, strlen(timer_exception_source),
        34, fixture->diagnostic, sizeof(fixture->diagnostic)
    );
    fixture->failures += mwx_fixture_check(
        fixture->timer_exception != NULL, "timer exception owner compile", fixture->diagnostic
    );
    fixture->failures += mwx_fixture_update_at(
        fixture->timer_exception, 34, 1, 0, 0,
        MWX_SCENE_QUICKJS_OK, 1, "timer exception initialization"
    );
    fixture->failures += mwx_fixture_update_at(
        fixture->timer_exception, 34, 1, 0.01, 0.01,
        MWX_SCENE_QUICKJS_EXCEPTION, 0, "timer exception disables owner"
    );
    fixture->failures += mwx_fixture_update(
        fixture->isolated, 2, 3, MWX_SCENE_QUICKJS_OK, 13,
        "timer exception preserves peer owner"
    );

    shared_cancel_outcomes(fixture);
    shared_cancel_snapshots(fixture);
    shared_cancel_permissions(fixture);
    shared_cancel_retirement(fixture);
    timer_allocation_pressure(fixture);
}
