#include "SceneScriptQuickJSFixture.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

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
        MWX_SCENE_QUICKJS_EXCEPTION, 0, "cross-owner timer cancel rejected"
    );
    fixture->failures += mwx_fixture_check(
        mwx_scene_quickjs_owner_active_timer_count(fixture->timer_cancel_owner) == 1,
        "cross-owner cancel preserves timer", ""
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

}
