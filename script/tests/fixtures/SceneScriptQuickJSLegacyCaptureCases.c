#include "SceneQuickJS.h"
#include "quickjs.h"

#include <stdio.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

/* Entirely owned inputs exercise the native intrinsic and the real Scene
 * timer boundary. No author source or alternate RegExp implementation. */
typedef struct {
    const char *label;
    const char *source;
} LegacyCase;

static const LegacyCase cases[] = {
    {"initial nine empty", "Array.from({length:9},(_,i)=>RegExp['$'+(i+1)]).every(v=>v==='')"},
    {"literal test", "/(bud)/.test('bud') && RegExp.$1==='bud'"},
    {"constructor exec", "new RegExp('(leaf)').exec('leaf')[1]==='leaf' && RegExp.$1==='leaf'"},
    {"renamed equivalent", "const renamed=new RegExp('(twig)',''); const text='twig'; renamed['test'](text); RegExp['$1']==='twig'"},
    {"borrowed exec", "RegExp.prototype.exec.call(/(root)/,'root'); RegExp.$1==='root'"},
    {"failed match retains", "/(stem)/.test('stem'); /absent/.test('twig'); RegExp.$1==='stem'"},
    {"no group clears", "/(stem)/.test('stem'); /twig/.test('twig'); RegExp.$1==='' && RegExp.$9===''"},
    {"optional group", "const r=/(a)?(b)/.exec('b'); r[1]===undefined && RegExp.$1==='' && RegExp.$2==='b'"},
    {"capture range shrinks and clears tail", "/(a)(b)(c)(d)(e)(f)(g)(h)(i)/.test('abcdefghi');/(leaf)/.test('leaf');RegExp.$1==='leaf' && Array.from({length:8},(_,i)=>RegExp['$'+(i+2)]).every(v=>v==='')"},
    {"fastpath range expands and clears", "/(held)/.test('held');'abcdefghi'.replace(/(a)(b)(c)(d)(e)(f)(g)(h)(i)/g,'');const nine=RegExp.$9==='i';'leaf'.replace(/leaf/g,'');nine && Array.from({length:9},(_,i)=>RegExp['$'+(i+1)]).every(v=>v==='')"},
    {"optional tail clears prior value", "/(a)(b)(c)/.test('abc');'a'.replace(/(a)(b)?/g,'');RegExp.$1==='a' && RegExp.$2==='' && RegExp.$3==='';"},
    {"invalid state restores empty via fastpath", "class Pattern extends RegExp{}new Pattern('(sub)').test('sub');let bad=false;try{RegExp.$1}catch(e){bad=e instanceof TypeError}'leaf'.replace(/leaf/g,'');bad && Array.from({length:9},(_,i)=>RegExp['$'+(i+1)]).every(v=>v==='')"},
    {"nine group limit", "/(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)/.test('abcdefghij'); RegExp.$1==='a' && RegExp.$9==='i' && !('$10' in RegExp)"},
    {"unicode capture", "/(🌿)/u.test('🌿'); RegExp.$1==='🌿' && RegExp.$1.length===2"},
    {"indices capture", "const r=/(b)/d.exec('ab'); r.indices[1][0]===1 && RegExp.$1==='b'"},
    {"named group", "const r=/(?<part>oak)/.exec('oak'); r.groups.part==='oak' && RegExp.$1==='oak'"},
    {"string match", "'bark'.match(/(bark)/)[1]==='bark' && RegExp.$1==='bark'"},
    {"global match", "'ab'.match(/(.)/g).join('')==='ab' && RegExp.$1==='b'"},
    {"string search", "'pine'.search(/(pine)/)===0 && RegExp.$1==='pine'"},
    {"string split", "'oak,elm'.split(/(,)/).length===3 && RegExp.$1===','"},
    {"matchAll cadence", "const it='ab'.matchAll(/(.)/g); it.next().value[1]==='a' && RegExp.$1==='a' && it.next().value[1]==='b' && RegExp.$1==='b' && it.next().done && RegExp.$1==='b'"},
    {"global replace", "'ab'.replace(/(.)/g,'$1$1')==='aabb' && RegExp.$1==='b'"},
    {"empty replacement fastpath", "'xayb'.replace(/([xy])/g,'')==='ab' && RegExp.$1==='y'"},
    {"zero length global", "const rx=/()/g;'ab'.replace(rx,'')==='ab' && RegExp.$1==='' && rx.lastIndex===0"},
    {"optional fastpath", "'b'.replace(/(a)?(b)/g,'')==='' && RegExp.$1==='' && RegExp.$2==='b'"},
    {"wide fastpath", "'🌿x🌿'.replace(/(🌿)/gu,'')==='x' && RegExp.$1==='🌿'"},
    {"nested replacer order", "const seen=[]; 'ab'.replace(/(.)/g,()=>{seen.push(RegExp.$1);/(inner)/.test('inner');return '';}); seen.join(',')==='b,inner' && RegExp.$1==='inner'"},
    {"throwing replacer retains native match", "try{'ab'.replace(/(.)/g,()=>{throw Error('owned');});}catch(e){} RegExp.$1==='b'"},
    {"custom exec fake result", "/(held)/.test('held'); const rx=/real/; rx.exec=()=>['fake','fake-capture']; rx.test('real'); RegExp.$1==='held'"},
    {"custom exec delegation", "const native=RegExp.prototype.exec; const rx=/(delegated)/; rx.exec=function(s){return native.call(this,s)}; rx.test('delegated') && RegExp.$1==='delegated'"},
    {"subclass invalidates", "class Pattern extends RegExp{}; new Pattern('(sub)').test('sub'); let bad=false;try{RegExp.$1}catch(e){bad=e instanceof TypeError} bad"},
    {"subclass failed retains", "/(held)/.test('held'); class Pattern extends RegExp{}; new Pattern('absent').test('sub'); RegExp.$1==='held'"},
    {"invalidation and recovery", "class Pattern extends RegExp{}; new Pattern('(sub)').test('sub'); /absent/.test('a'); let bad=false;try{RegExp.$1}catch(e){bad=e instanceof TypeError} /(restored)/.test('restored'); bad && RegExp.$1==='restored'"},
    {"Reflect foreign target", "function Foreign(){} Foreign.prototype=RegExp.prototype; Reflect.construct(RegExp,['(ref)'],Foreign).test('ref'); let bad=false;try{RegExp.$1}catch(e){bad=e instanceof TypeError} bad"},
    {"Reflect intrinsic target", "Reflect.construct(RegExp,['(ref)'],RegExp).test('ref'); RegExp.$1==='ref'"},
    {"bound newTarget", "const target=RegExp.bind(null); new target('(bound)').test('bound'); RegExp.$1==='bound'"},
    {"prototype mutation eligible", "const rx=/(seed)/; Object.setPrototypeOf(rx,null); RegExp.prototype.exec.call(rx,'seed'); RegExp.$1==='seed'"},
    {"constructor mutation eligible", "const rx=/(seed)/; rx.constructor=function Other(){}; rx.test('seed'); RegExp.$1==='seed'"},
    {"subclass prototype mutation ineligible", "class Pattern extends RegExp{} const rx=new Pattern('(sub)'); Object.setPrototypeOf(rx,RegExp.prototype); rx.constructor=RegExp; rx.test('sub'); let bad=false;try{RegExp.$1}catch(e){bad=e instanceof TypeError} bad"},
    {"subclass fastpath invalidates", "class Pattern extends RegExp{}const rx=new Pattern('(sub)','g');rx.constructor=RegExp;'sub'.replace(rx,'');let bad=false;try{RegExp.$1}catch(e){bad=e instanceof TypeError}bad"},
    {"proxy newTarget remains ineligible", "const Target=new Proxy(RegExp,{});new Target('(proxy)').test('proxy');let bad=false;try{RegExp.$1}catch(e){bad=e instanceof TypeError}bad"},
    {"constructor identity return retains eligibility", "class Pattern extends RegExp{}const rx=new Pattern('(sub)');rx.constructor=RegExp;RegExp(rx)===rx && rx.test('sub');let bad=false;try{RegExp.$1}catch(e){bad=e instanceof TypeError}bad"},
    {"global rebinding preserves intrinsic", "const Intrinsic=RegExp;const rx=/(seed)/;globalThis.RegExp=function Other(){};Intrinsic.prototype.exec.call(rx,'seed');Intrinsic.$1==='seed'"},
    {"native descriptors", "const d=Object.getOwnPropertyDescriptor(RegExp,'$1'); d.configurable && !d.enumerable && d.set===undefined && d.get.length===0 && RegExp.prototype.exec.name==='exec' && RegExp.prototype.exec.length===1 && RegExp.prototype.exec.toString().includes('[native code]')"},
    {"getter wrong receiver", "const g=Object.getOwnPropertyDescriptor(RegExp,'$1').get; let bad=false;try{g.call({})}catch(e){bad=e instanceof TypeError} bad && g.call(RegExp)===''"},
    {"subclass getter receiver", "class Pattern extends RegExp{} let bad=false;try{Pattern.$1}catch(e){bad=e instanceof TypeError} bad"},
    {"strict assignment rejects", "let bad=false;try{(()=>{'use strict';RegExp.$1='forged'})()}catch(e){bad=e instanceof TypeError} bad && RegExp.$1===''"},
    {"delete stays deleted", "delete RegExp.$1; /(gone)/.test('gone'); !Object.hasOwn(RegExp,'$1') && RegExp.$1===undefined && RegExp.$2===''"},
    {"native result no callback getters", "let count=0; Object.defineProperty(Array.prototype,'1',{get(){count++;return 'forged'},configurable:true}); const r=/(native)/.exec('native'); delete Array.prototype[1]; count===0 && r[1]==='native' && RegExp.$1==='native'"},
    {"throwing fastpath exec getter", "/(held)/.test('held');const rx=/(new)/g;Object.defineProperty(rx,'exec',{get(){throw Error('owned-exec')}});let bad=false;try{'new'.replace(rx,'')}catch(e){bad=e.message==='owned-exec'}bad && RegExp.$1==='held'"},
    {"throwing fastpath constructor getter", "/(held)/.test('held');const rx=/(new)/g;Object.defineProperty(rx,'constructor',{get(){throw Error('owned-constructor')}});let bad=false;try{'new'.replace(rx,'')}catch(e){bad=e.message==='owned-constructor'}bad && RegExp.$1==='held'"},
    {"fastpath exec getter freezes lastIndex", "/(held)/.test('held');const rx=/(new)/g;Object.defineProperty(rx,'exec',{get(){Object.freeze(rx);return RegExp.prototype.exec}});let bad=false;try{'new'.replace(rx,'')}catch(e){bad=e instanceof TypeError}bad && RegExp.$1==='held'"},
    {"fastpath lastIndex conversion freezes receiver", "/(held)/.test('held');const rx=/(new)/g;Object.defineProperty(rx,'exec',{get(){rx.lastIndex={valueOf(){Object.freeze(rx);return 0}};return RegExp.prototype.exec}});let bad=false;try{'new'.replace(rx,'')}catch(e){bad=e instanceof TypeError}bad && RegExp.$1==='held'"},
    {"ineligible failed write retains validity", "/(held)/.test('held');class Pattern extends RegExp{}const rx=new Pattern('(new)','g');rx.constructor=RegExp;Object.defineProperty(rx,'exec',{get(){Object.freeze(rx);return RegExp.prototype.exec}});let bad=false;try{'new'.replace(rx,'')}catch(e){bad=e instanceof TypeError}bad && RegExp.$1==='held'"},
};

static int check_expression(JSContext *ctx, const char *label, const char *source) {
    JSValue result=JS_Eval(ctx,source,strlen(source),"owned-legacy.js",JS_EVAL_TYPE_GLOBAL);
    int failed=JS_IsException(result) || JS_ToBool(ctx,result)!=1;
    if(failed) {
        JSValue error=JS_IsException(result)?JS_GetException(ctx):JS_DupValue(ctx,result);
        const char *message=JS_ToCString(ctx,error);
        fprintf(stderr,"legacy capture %s: %s\n",label,message?message:"exception");
        JS_FreeCString(ctx,message);
        JS_FreeValue(ctx,error);
    }
    JS_FreeValue(ctx,result);
    return failed;
}

static int raw_cases(void) {
    int failures=0;
    JSRuntime *rt=JS_NewRuntime();
    if(!rt) return 1;
    for(size_t i=0;i<sizeof(cases)/sizeof(cases[0]);i++) {
        JSContext *ctx=JS_NewContext(rt);
        if(!ctx) {failures++;break;}
        failures+=check_expression(ctx,cases[i].label,cases[i].source);
        JS_FreeContext(ctx);
        JS_RunGC(rt);
    }
    JS_FreeRuntime(rt);
    return failures;
}

static int set_foreign(JSContext *ctx,const char *name,JSValue value) {
    JSValue global=JS_GetGlobalObject(ctx);
    int failed=JS_SetPropertyStr(ctx,global,name,value)<0;
    JS_FreeValue(ctx,global);
    return failed;
}

static JSValue own_eval(JSContext *ctx,const char *source) {
    return JS_Eval(ctx,source,strlen(source),"owned-realm.js",JS_EVAL_TYPE_GLOBAL);
}

static int realm_cases(void) {
    int failures=0;
    JSRuntime *rt=JS_NewRuntime();
    JSContext *a=rt?JS_NewContext(rt):NULL;
    JSContext *b=rt?JS_NewContext(rt):NULL;
    if(!a || !b) {if(a)JS_FreeContext(a);if(b)JS_FreeContext(b);if(rt)JS_FreeRuntime(rt);return 1;}
    failures+=check_expression(a,"realm A seed","/(alpha)/.test('alpha');RegExp.$1==='alpha'");
    failures+=check_expression(b,"realm B seed","/(beta)/.test('beta');RegExp.$1==='beta'");
    failures+=set_foreign(a,"foreignRegex",own_eval(b,"/(foreign)/"));
    failures+=set_foreign(a,"foreignExec",own_eval(b,"RegExp.prototype.exec"));
    failures+=set_foreign(a,"foreignCtor",own_eval(b,"RegExp"));
    failures+=set_foreign(a,"foreignGetter",own_eval(b,"Object.getOwnPropertyDescriptor(RegExp,'$1').get"));
    failures+=check_expression(a,"A exec foreign regex no update","RegExp.prototype.exec.call(foreignRegex,'foreign');RegExp.$1==='alpha'");
    failures+=check_expression(b,"B unchanged by A exec","RegExp.$1==='beta'");
    failures+=check_expression(a,"B exec A regex no update","foreignExec.call(/(local)/,'local');RegExp.$1==='alpha'");
    failures+=check_expression(b,"B unchanged by foreign input","RegExp.$1==='beta'");
    failures+=check_expression(a,"foreign getter intrinsic receiver","foreignGetter.call(foreignCtor)==='beta'");
    failures+=check_expression(a,"foreign getter wrong receiver","let bad=false;try{foreignGetter.call(RegExp)}catch(e){bad=e.name==='TypeError'} bad");
    failures+=check_expression(a,"B exec B regex updates B only","foreignExec.call(foreignRegex,'foreign');RegExp.$1==='alpha' && foreignGetter.call(foreignCtor)==='foreign'");
    failures+=check_expression(a,"foreign constructor realm","const rx=new foreignCtor('(remote)');rx.test('remote');RegExp.$1==='alpha' && foreignGetter.call(foreignCtor)==='remote'");
    failures+=check_expression(a,"foreign exec fastpath does not publish to A","const nativeForeign=/(fast)/g;nativeForeign.exec=foreignExec;'fast'.replace(nativeForeign,'')==='' && RegExp.$1==='alpha' && foreignGetter.call(foreignCtor)==='remote'");
    failures+=check_expression(a,"foreign exec fastpath publishes to B","const fastB=new foreignCtor('(fast-b)','g');fastB.constructor=RegExp;const replaced=RegExp.prototype[Symbol.replace].call(fastB,'fast-b','');const observed=foreignGetter.call(foreignCtor)==='fast-b';foreignExec.call(foreignRegex,'foreign');replaced==='' && observed && RegExp.$1==='alpha'");
    failures+=check_expression(a,"foreign Reflect prototype chooses B exec","const mixed=Reflect.construct(RegExp,['(mixed)'],foreignCtor);mixed.test('mixed');RegExp.$1==='alpha' && foreignGetter.call(foreignCtor)==='foreign'");
    failures+=check_expression(a,"foreign Reflect newTarget A exec invalidates","RegExp.prototype.exec.call(mixed,'mixed');let bad2=false;try{RegExp.$1}catch(e){bad2=e instanceof TypeError}bad2");
    failures+=check_expression(a,"recover A before GC","/(alpha)/.test('alpha');Object.setPrototypeOf(foreignRegex,null);RegExp.$1==='alpha'");
    JS_FreeContext(b);
    JS_RunGC(rt);
    failures+=check_expression(a,"foreign creator survives context release","foreignExec.call(foreignRegex,'foreign');foreignGetter.call(foreignCtor)==='foreign' && RegExp.$1==='alpha'");
    failures+=check_expression(a,"cycles collected","foreignRegex=foreignExec=foreignCtor=foreignGetter=null;for(let i=0;i<100;i++){const rx=/(cycle)/;rx.loop=rx;Object.setPrototypeOf(rx,null)} true");
    JS_RunGC(rt);
    JS_FreeContext(a);
    JS_RunGC(rt);
    JS_FreeRuntime(rt);
    return failures;
}

static JSValue owned_collect(JSContext *ctx,JSValueConst this_value,
                            int argc,JSValueConst *argv) {
    (void)this_value;(void)argc;(void)argv;
    JS_RunGC(JS_GetRuntime(ctx));
    return JS_UNDEFINED;
}

static int borrowed_realm_lifetime_cases(void) {
    int failures=0;
    for(int throws=0;throws<2;throws++) {
        JSRuntime *rt=JS_NewRuntime();
        JSContext *a=rt?JS_NewContext(rt):NULL;
        JSContext *b=rt?JS_NewContext(rt):NULL;
        if(!a || !b){if(a)JS_FreeContext(a);if(b)JS_FreeContext(b);if(rt)JS_FreeRuntime(rt);return failures+1;}
        JS_SetDumpFlags(rt,JS_ABORT_ON_LEAKS);
        failures+=set_foreign(a,"foreignExec",own_eval(b,"RegExp.prototype.exec"));
        failures+=set_foreign(a,"ownedCollect",JS_NewCFunction(a,owned_collect,"ownedCollect",0));
        JS_FreeContext(b);
        const char *success="/(held)/.test('held');const rx=/a/g;Object.defineProperty(rx,'exec',{get(){const out=foreignExec;foreignExec=null;rx.lastIndex={valueOf(){ownedCollect();return 0}};return out}});'a'.replace(rx,'')==='' && RegExp.$1==='held'";
        const char *exception="/(held)/.test('held');const rx=/a/g;Object.defineProperty(rx,'exec',{get(){const out=foreignExec;foreignExec=null;rx.lastIndex={valueOf(){ownedCollect();throw Error('owned-realm-exception')}};return out}});let caught=false;try{'a'.replace(rx,'')}catch(e){caught=e.message==='owned-realm-exception'}caught && RegExp.$1==='held'";
        failures+=check_expression(a,throws?"borrowed realm held through exception GC":"borrowed realm held through success GC",throws?exception:success);
        JS_RunGC(rt);
        JS_FreeContext(a);
        JS_RunGC(rt);
        JS_FreeRuntime(rt);
    }
    return failures;
}

static int timer_cases(void) {
    const char *source="'use strict';let out='pending';export function init(value){engine.setInterval(function(){/(owned)/.test('owned');out=String(RegExp.$1.length);},1);return value;}export function update(value){return out;}";
    char diagnostic[512]={0},output[64]={0};size_t length=0;
    MWXSceneQuickJSDomain *domain=mwx_scene_quickjs_domain_create(2*1024*1024,512*1024,100000,diagnostic,sizeof(diagnostic));
    if(!domain) return 1;
    MWXSceneQuickJSOwner *owner=mwx_scene_quickjs_owner_create(domain,source,strlen(source),1,diagnostic,sizeof(diagnostic));
    if(!owner){mwx_scene_quickjs_domain_destroy(domain);return 1;}
    MWXSceneQuickJSFrameInput frame={.time_of_day=0.25,.frame_time=0,.runtime=0};
    MWXSceneQuickJSResult first=mwx_scene_quickjs_owner_update_string(owner,1,"owned",5,&frame,"",0,"{}",2,output,sizeof(output),&length,diagnostic,sizeof(diagnostic));
    int failures=first!=MWX_SCENE_QUICKJS_OK || strcmp(output,"pending")!=0;
    if(first==MWX_SCENE_QUICKJS_OK)mwx_scene_quickjs_owner_commit_layer_mutations(owner);
    frame.frame_time=0.002;frame.runtime=0.002;
    MWXSceneQuickJSResult next=mwx_scene_quickjs_owner_update_string(owner,1,"owned",5,&frame,"",0,"{}",2,output,sizeof(output),&length,diagnostic,sizeof(diagnostic));
    failures+=next!=MWX_SCENE_QUICKJS_OK || strcmp(output,"5")!=0;
    if(next==MWX_SCENE_QUICKJS_OK)mwx_scene_quickjs_owner_commit_layer_mutations(owner);
    if(failures)fprintf(stderr,"legacy Scene timer: %s\n",diagnostic);
    mwx_scene_quickjs_owner_destroy(owner);
    mwx_scene_quickjs_domain_destroy(domain);
    return failures;
}

/* A public QuickJS allocator supplies deterministic failure at every native
 * allocation in a compiled call. It tests atomic publication, including OOM
 * after some capture strings exist, without changing the product budget. */
typedef union {
    max_align_t alignment;
    struct {size_t size;} data;
} TestBlock;

typedef struct {
    size_t fail_at;
    size_t calls;
    size_t live;
    int active;
} TestAllocator;

static int allocation_fails(TestAllocator *state,size_t size) {
    if(!state->active) return 0;
    state->calls++;
    if(state->calls!=state->fail_at) return 0;
    (void)size;
    return 1;
}

static void *test_malloc(void *opaque,size_t size) {
    TestAllocator *state=opaque;
    if(allocation_fails(state,size) || size>SIZE_MAX-sizeof(TestBlock))return NULL;
    TestBlock *block=malloc(sizeof(TestBlock)+size);
    if(!block)return NULL;
    block->data.size=size;
    state->live++;
    return block+1;
}

static void *test_calloc(void *opaque,size_t count,size_t size) {
    if(count && size>SIZE_MAX/count)return NULL;
    size_t total=count*size;
    void *result=test_malloc(opaque,total);
    if(result)memset(result,0,total);
    return result;
}

static void test_free(void *opaque,void *pointer) {
    if(!pointer)return;
    TestAllocator *state=opaque;
    state->live--;
    free((TestBlock *)pointer-1);
}

static void *test_realloc(void *opaque,void *pointer,size_t size) {
    if(!pointer)return test_malloc(opaque,size);
    if(!size){test_free(opaque,pointer);return NULL;}
    TestAllocator *state=opaque;
    if(allocation_fails(state,size) || size>SIZE_MAX-sizeof(TestBlock))return NULL;
    TestBlock *block=realloc((TestBlock *)pointer-1,sizeof(TestBlock)+size);
    if(!block)return NULL;
    block->data.size=size;
    return block+1;
}

static size_t test_usable_size(const void *pointer) {
    return pointer?((const TestBlock *)pointer-1)->data.size:0;
}

static void clear_exception(JSContext *ctx) {
    JSValue exception=JS_GetException(ctx);
    JS_FreeValue(ctx,exception);
}

static JSValue work_function(JSContext *ctx) {
    JSValue global=JS_GetGlobalObject(ctx);
    JSValue work=JS_GetPropertyStr(ctx,global,"work");
    JS_FreeValue(ctx,global);
    return work;
}

static int allocation_cases(void) {
    const JSMallocFunctions allocator={test_calloc,test_malloc,test_free,test_realloc,test_usable_size};
    const char *setup="globalThis.input=Array.from({length:9},(_,i)=>String.fromCharCode(97+i).repeat(1500)).join('');globalThis.rx=/(a+)(b+)(c+)(d+)(e+)(f+)(g+)(h+)(i+)/g;globalThis.work=()=>input.replace(rx,'');/(1)(2)(3)(4)(5)(6)(7)(8)(9)/.test('123456789');true";
    const char *atomic="const c=Array.from({length:9},(_,i)=>RegExp['$'+(i+1)]);c.every((v,i)=>v===String(i+1)) || c.every((v,i)=>v===String.fromCharCode(97+i).repeat(1500))";
    size_t baseline_calls=0,failures_seen=0;
    int failures=0;
    /* First call establishes the allocation count, then each ordinal is
     * rejected once in a fresh runtime with identical owned inputs. */
    for(size_t ordinal=0;ordinal<=baseline_calls;ordinal++) {
        TestAllocator state={.fail_at=ordinal};
        JSRuntime *rt=JS_NewRuntime2(&allocator,&state);
        JSContext *ctx=rt?JS_NewContext(rt):NULL;
        if(!ctx){if(rt)JS_FreeRuntime(rt);return failures+1;}
        JS_SetDumpFlags(rt,JS_ABORT_ON_LEAKS);
        failures+=check_expression(ctx,"allocation fixture prepared",setup);
        JSValue work=work_function(ctx);
        state.active=1;
        JSValue result=JS_Call(ctx,work,JS_UNDEFINED,0,NULL);
        state.active=0;
        int rejected=JS_IsException(result);
        if(!rejected && JS_HasException(ctx)) {
            fprintf(stderr,"legacy capture successful result left a pending exception at ordinal=%zu\n",ordinal);
            failures++;
        }
        if(ordinal==0) {
            baseline_calls=state.calls;
            failures+=rejected || baseline_calls==0;
        } else {
            failures_seen+=rejected;
        }
        clear_exception(ctx);
        JS_FreeValue(ctx,result);
        JS_FreeValue(ctx,work);
        failures+=check_expression(ctx,"nine captures never partially publish",atomic);
        JS_FreeContext(ctx);
        JS_RunGC(rt);
        JS_FreeRuntime(rt);
        failures+=state.live!=0;
    }
    if(failures_seen==0) {
        fprintf(stderr,"legacy capture allocation coverage: calls=%zu rejected=%zu\n",baseline_calls,failures_seen);
        failures++;
    }
    printf("legacy capture allocation ordinals=%zu rejected=%zu atomic-nine=true\n",baseline_calls,failures_seen);
    return failures;
}

static int memory_limit_cases(void) {
    int failures=0;
    for(int limited=0;limited<2;limited++) {
        JSRuntime *rt=JS_NewRuntime();
        JSContext *ctx=rt?JS_NewContext(rt):NULL;
        if(!ctx){if(rt)JS_FreeRuntime(rt);return failures+1;}
        failures+=check_expression(ctx,"output budget fixture prepared","globalThis.input='xY'.repeat(25000);globalThis.rx=/(x)/g;globalThis.work=()=>input.replace(rx,'');/(held)(old)/.test('heldold');true");
        JSValue work=work_function(ctx);
        JSMemoryUsage usage;
        JS_ComputeMemoryUsage(rt,&usage);
        if(limited)JS_SetMemoryLimit(rt,(size_t)usage.malloc_size+8192);
        JSValue result=JS_Call(ctx,work,JS_UNDEFINED,0,NULL);
        int rejected=JS_IsException(result);
        JS_SetMemoryLimit(rt,0);
        clear_exception(ctx);
        if(rejected!=limited) {
            fprintf(stderr,"legacy capture native memory limit: expected rejection=%d actual=%d\n",limited,rejected);
            failures++;
        }
        if(!rejected) {
            size_t length=0;
            const char *output=JS_ToCStringLen(ctx,&length,result);
            failures+=!output || length!=25000;
            JS_FreeCString(ctx,output);
        }
        JS_FreeValue(ctx,result);
        JS_FreeValue(ctx,work);
        failures+=check_expression(ctx,"output OOM retains completed native match","RegExp.$1==='x' && RegExp.$2===''");
        JS_FreeContext(ctx);
        JS_RunGC(rt);
        JS_FreeRuntime(rt);
    }
    return failures;
}

static int interrupt_after_three(JSRuntime *rt,void *opaque) {
    (void)rt;
    int *calls=opaque;
    return ++*calls>3;
}

static int interrupt_case(void) {
    int failures=0,calls=0;
    JSRuntime *rt=JS_NewRuntime();
    JSContext *ctx=rt?JS_NewContext(rt):NULL;
    if(!ctx){if(rt)JS_FreeRuntime(rt);return 1;}
    failures+=check_expression(ctx,"interrupt fixture prepared","globalThis.input='a'.repeat(24)+'c';globalThis.rx=/(a+)+b/g;globalThis.work=()=>input.replace(rx,'');/(held)/.test('held');true");
    JSValue work=work_function(ctx);
    JS_SetInterruptHandler(rt,interrupt_after_three,&calls);
    JSValue result=JS_Call(ctx,work,JS_UNDEFINED,0,NULL);
    failures+=!JS_IsException(result) || calls<=3;
    JS_SetInterruptHandler(rt,NULL,NULL);
    clear_exception(ctx);
    JS_FreeValue(ctx,result);
    JS_FreeValue(ctx,work);
    failures+=check_expression(ctx,"interruption retains prior completed state","RegExp.$1==='held' && RegExp.$2===''");
    JS_FreeContext(ctx);
    JS_RunGC(rt);
    JS_FreeRuntime(rt);
    return failures;
}

static int detached_capture_cases(void) {
    const char *sources[]={
        "(()=>{/(a+)/.test('a'.repeat(1025)+'z'.repeat(1<<20))})()",
        "(()=>{('a'.repeat(1025)+'z'.repeat(1<<20)).replace(/(a+)/g,'')})()",
        "(()=>{/(🌿+)/u.test('🌿'.repeat(1025)+'界'.repeat(1<<20))})()",
        "(()=>{('🌿'.repeat(1025)+'界'.repeat(1<<20)).replace(/(🌿+)/gu,'')})()",
        "(()=>{const s=('z'.repeat(1<<20)+'a'.repeat(1025)+'z'.repeat(1<<20)).substring(1<<20,(1<<20)+1025);/(a+)/.test(s)})()"
    };
    int failures=0;
    for(size_t i=0;i<sizeof(sources)/sizeof(sources[0]);i++) {
        JSRuntime *rt=JS_NewRuntime();JSContext *ctx=rt?JS_NewContext(rt):NULL;
        if(!ctx){if(rt)JS_FreeRuntime(rt);return failures+1;}
        JS_SetDumpFlags(rt,JS_ABORT_ON_LEAKS);
        JSMemoryUsage before,after;JS_ComputeMemoryUsage(rt,&before);
        JSValue result=own_eval(ctx,sources[i]);
        failures+=JS_IsException(result);clear_exception(ctx);JS_FreeValue(ctx,result);
        JS_RunGC(rt);JS_ComputeMemoryUsage(rt,&after);
        int64_t retained=after.malloc_size-before.malloc_size;
        if(retained>64*1024) {
            fprintf(stderr,"legacy capture retained unrelated input case=%zu bytes=%lld\n",i,(long long)retained);
            failures++;
        }
        if(after.memory_used_size-before.memory_used_size<(i==2 || i==3?4100:1025)) {
            fprintf(stderr,"legacy capture memory estimate missed context strings case=%zu\n",i);
            failures++;
        }
        failures+=check_expression(ctx,"detached captures preserve code units",
            i==2 || i==3?"RegExp.$1==='🌿'.repeat(1025)":"RegExp.$1==='a'.repeat(1025)");
        printf("legacy detached capture case=%zu retainedBytes=%lld\n",i,(long long)retained);
        JS_FreeContext(ctx);JS_RunGC(rt);JS_FreeRuntime(rt);
    }
    return failures;
}

int mwx_test_legacy_capture_cases(void) {
    int results[]={raw_cases(),realm_cases(),borrowed_realm_lifetime_cases(),timer_cases(),allocation_cases(),memory_limit_cases(),interrupt_case(),detached_capture_cases()};
    const char *labels[]={"intrinsic","realm","borrowed-realm-lifetime","timer","allocation","memory-limit","interrupt","detached"};
    int failures=0;
    for(size_t i=0;i<sizeof(results)/sizeof(results[0]);i++) {
        if(results[i])fprintf(stderr,"legacy capture %s failures=%d\n",labels[i],results[i]);
        failures+=results[i];
    }
    return failures;
}
