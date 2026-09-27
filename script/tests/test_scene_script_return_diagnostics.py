"""Sanitized real-VM regression for temporary Vec3 return-value diagnostics."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

from .scene_vector_vm_test_support import C_SOURCES, VM, QUICKJS

HARNESS = r'''
#include "SceneQuickJS.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

static int check(int ok, const char *label, const char *diagnostic) {
    if (!ok) fprintf(stderr, "%s: %s\n", label, diagnostic);
    return !ok;
}

static int vector_dimensions(int mode) {
    char message[512] = {0}; int failures = 0;
    MWXSceneQuickJSDomain *d = mwx_scene_quickjs_domain_create(
        8*1024*1024,512*1024,100000,message,sizeof(message));
    if (!d) return check(0,"dimension domain",message);
    const char *sources[] = {
        "let n=0; export function init(v){if(!(v instanceof Vec2)||'z' in v||++n!==1)throw Error('input type or repeated init');return new Vec2(3,5);} export function update(v){if(!(v instanceof Vec2))throw Error('update type');return v.add(new Vec2(1,2));}",
        "export function init(v){if(!(v instanceof Vec2))throw Error('init type');return new Vec2(v.y,v.x);}",
        "export function update(v){return 4;}",
        "export function update(v){return '3 5';}",
        "export function update(v){return engine.runtime===1 ? {x:4} : v;}",
        "export function update(v){return engine.runtime===1 ? new Vec2(1,NaN) : v;}",
        "export function update(v){return engine.runtime===1 ? new Vec2(1,2) : v;}",
        "export function update(v){throw Error('must not enter callback');}",
        "export function update(v){throw Error('must not enter callback');}",
        "export function update(v){throw Error('must not enter callback');}",
    };
    int variant = mode - 7; const char *source = sources[variant];
    MWXSceneQuickJSOwner *o = mwx_scene_quickjs_owner_create(d,source,strlen(source),1,message,sizeof(message));
    if (!o) return check(0,"dimension owner",message);
    uint32_t dimensions = variant == 6 ? 3 : 2;
    // Exact allocations let ASan detect an accidental third input read/output write.
    double *input=malloc(sizeof(double)*dimensions), *output=malloc(sizeof(double)*dimensions);
    for (uint32_t i=0;i<dimensions;++i) { input[i]=7+i;output[i]=-99; }
    MWXSceneQuickJSFrameInput f={.time_of_day=.25,.frame_time=.016,.runtime=1};
    uint32_t initialized=0;
    MWXSceneQuickJSResult result;
    if (variant == 7) {
        const uint32_t invalid[]={0,1,4,UINT32_MAX};
        for (size_t i=0;i<4;++i) {
            result=mwx_scene_quickjs_owner_initialize_vector(o,1,input,invalid[i],&f,"",0,"{}",2,output,&initialized,message,sizeof(message));
            failures+=check(result==MWX_SCENE_QUICKJS_INVALID_ARGUMENT && output[0]==-99 && output[1]==-99,"invalid init dimensions",message);
            result=mwx_scene_quickjs_owner_update_vector(o,1,input,invalid[i],&f,"",0,"{}",2,output,message,sizeof(message));
            failures+=check(result==MWX_SCENE_QUICKJS_INVALID_ARGUMENT && output[0]==-99 && output[1]==-99,"invalid update dimensions",message);
        }
    } else {
        if (variant==9) input[1]=INFINITY;
        if (variant==1) result=mwx_scene_quickjs_owner_initialize_vector(o,1,input,dimensions,&f,"",0,"{}",2,output,&initialized,message,sizeof(message));
        else result=mwx_scene_quickjs_owner_update_vector(o,variant==8?2:1,input,dimensions,&f,"",0,"{}",2,output,message,sizeof(message));
        MWXSceneQuickJSResult expected=variant>=4&&variant<=6?MWX_SCENE_QUICKJS_BAD_RETURN:variant==8?MWX_SCENE_QUICKJS_STALE_OWNER:variant==9?MWX_SCENE_QUICKJS_INVALID_ARGUMENT:MWX_SCENE_QUICKJS_OK;
        failures+=check(result==expected,"typed vector outcome",message);
        if (variant<=3) {
            double x[]={4,8,4,3},y[]={7,7,4,5};
            failures+=check(output[0]==x[variant]&&output[1]==y[variant],"typed vector result",message);
        }
        if (variant==0) {
            mwx_scene_quickjs_owner_commit_layer_mutations(o);
            result=mwx_scene_quickjs_owner_update_vector(o,1,input,2,&f,"",0,"{}",2,output,message,sizeof(message));
            failures+=check(result==MWX_SCENE_QUICKJS_OK&&output[0]==8&&output[1]==10,"init committed once",message);
        }
        if (variant==1) failures+=check(initialized==1,"out of band init",message);
        if (variant>=4&&variant<=6) {
            f.runtime=2;
            result=mwx_scene_quickjs_owner_update_vector(o,1,input,dimensions,&f,"",0,"{}",2,output,message,sizeof(message));
            failures+=check(result==MWX_SCENE_QUICKJS_OK&&output[0]==7&&output[1]==8&&(dimensions==2||output[2]==9),"typed return recovery",message);
        }
    }
    free(input);free(output);mwx_scene_quickjs_owner_destroy(o);mwx_scene_quickjs_domain_destroy(d);
    return failures?1:0;
}

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    int mode = atoi(argv[1]), failures = 0;
    if (mode >= 7 && mode <= 16) return vector_dimensions(mode);
    char diagnostic[512] = {0};
    MWXSceneQuickJSDomain *domain = mwx_scene_quickjs_domain_create(
        8*1024*1024, 512*1024, 100000, diagnostic, sizeof(diagnostic));
    if (!domain) return check(0, "domain", diagnostic);
    const char *sources[] = {
        "export function update(v){return engine.runtime===1 ? 'bad-'+engine.runtime : v;}",
        "export function update(v){return engine.runtime===1 ? 'invalid-'+engine.runtime+'x'.repeat(8192) : v;}",
        "export function update(v){return engine.runtime===1 ? '错误🌍'+engine.runtime+'界'.repeat(4096) : v;}",
        "export function init(v){return engine.runtime===1 ? 'init-'+engine.runtime+'x'.repeat(1024) : v;}",
        "export function update(v){return engine.runtime===1 ? 'bounded-'+engine.runtime : v;}",
        "export function update(v){return engine.runtime+' 2 3';}",
        "export function update(v){return engine.runtime===1 ? {} : v;}",
    };
    if (mode < 0 || mode >= 7) return 2;
    const char *source = sources[mode];
    MWXSceneQuickJSOwner *owner = mwx_scene_quickjs_owner_create(
        domain, source, strlen(source), 1, diagnostic, sizeof(diagnostic));
    if (!owner) return check(0, "owner", diagnostic);
    const char *peer_source = "export function update(v){return new Vec3(4,5,6);}";
    MWXSceneQuickJSOwner *peer = mwx_scene_quickjs_owner_create(
        domain, peer_source, strlen(peer_source), 1, diagnostic, sizeof(diagnostic));
    if (!peer) return check(0, "peer", diagnostic);
    const size_t capacities[] = {512, 1, 0, 8};
    const double input[] = {7,8,9};
    for (int iteration = 0; iteration < (mode == 4 ? 4 : 1); ++iteration) {
        // Red zones detect writes even when capacity is zero or one; ASan
        // instruments both the production host and all QuickJS C sources.
        unsigned char buffer[544]; memset(buffer, 0xA5, sizeof(buffer));
        char *message = (char *)&buffer[16];
        size_t capacity = mode == 4 ? capacities[iteration] : 512;
        double output[3] = {0}; uint32_t initialized = 0;
        MWXSceneQuickJSFrameInput frame = {.time_of_day=.25, .frame_time=.016, .runtime=1};
        MWXSceneQuickJSResult result;
        if (mode == 3) {
            result = mwx_scene_quickjs_owner_initialize_vector(owner,1,input, 3,&frame,
                "",0,"{}",2,output,&initialized,message,capacity);
        } else {
            result = mwx_scene_quickjs_owner_update_vector(owner,1,input, 3,&frame,
                "",0,"{}",2,output,message,capacity);
        }
        failures += check(result == (mode == 5 ? MWX_SCENE_QUICKJS_OK : MWX_SCENE_QUICKJS_BAD_RETURN),
                          "return classification", capacity ? message : "zero capacity");
        for (size_t i=0; i<16; ++i) failures += check(buffer[i]==0xA5,"prefix canary","");
        for (size_t i=16+capacity; i<sizeof(buffer); ++i)
            failures += check(buffer[i]==0xA5,"suffix canary","");
        if (capacity) failures += check(memchr(message,'\0',capacity)!=NULL,"bounded terminator","");
        if (capacity == 512 && mode != 5)
            failures += check(strstr(message,mode==6 ? "(returned object)" : "(returned string)")!=NULL,
                              "return shape diagnostic",message);
        if (mode == 5) failures += check(output[0]==1 && output[1]==2 && output[2]==3,"valid vector string","");
        if (mode == 3) failures += check(!mwx_scene_quickjs_owner_is_initialized(owner),"rejected init remains pending","");
        // Failed data leaves the owner retryable and an independent owner usable.
        frame.runtime = 2;
        if (mode == 3) {
            result = mwx_scene_quickjs_owner_initialize_vector(owner,1,input, 3,&frame,
                "",0,"{}",2,output,&initialized,diagnostic,sizeof(diagnostic));
        } else {
            result = mwx_scene_quickjs_owner_update_vector(owner,1,input, 3,&frame,
                "",0,"{}",2,output,diagnostic,sizeof(diagnostic));
        }
        failures += check(result==MWX_SCENE_QUICKJS_OK,"next frame recovery",diagnostic);
        failures += check(output[0]==(mode==5 ? 2 : 7) && output[1]==(mode==5 ? 2 : 8)
            && output[2]==(mode==5 ? 3 : 9),"recovered vector",diagnostic);
        mwx_scene_quickjs_owner_commit_layer_mutations(owner);
        result=mwx_scene_quickjs_owner_update_vector(peer,1,input, 3,&frame,"",0,"{}",2,
            output,diagnostic,sizeof(diagnostic));
        failures += check(result==MWX_SCENE_QUICKJS_OK && output[0]==4 && output[1]==5 && output[2]==6,
                          "independent peer",diagnostic);
        mwx_scene_quickjs_owner_commit_layer_mutations(peer);
    }
    mwx_scene_quickjs_owner_destroy(peer);
    mwx_scene_quickjs_owner_destroy(owner);
    mwx_scene_quickjs_domain_destroy(domain);
    return failures ? 1 : 0;
}
'''


class SceneScriptReturnDiagnosticTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        clang = shutil.which("clang")
        if not clang:
            raise unittest.SkipTest("clang is required for the sanitized VM gate")
        cls.temp = tempfile.TemporaryDirectory(prefix="scene-return-diagnostics-")
        root = Path(cls.temp.name)
        source = root / "harness.c"
        source.write_text(HARNESS)
        cls.binary = root / "harness"
        command = [clang, "-std=c11", "-O1", "-g", "-fsanitize=address",
                   "-fno-omit-frame-pointer", "-I", str(VM), "-I", str(QUICKJS),
                   *map(str, C_SOURCES), str(source), "-lm", "-o", str(cls.binary)]
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode:
            cls.temp.cleanup()
            raise AssertionError(result.stdout + result.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def run_case(self, mode):
        result = subprocess.run([str(self.binary), str(mode)], capture_output=True, text=True,
            env={**os.environ, "ASAN_OPTIONS": "detect_leaks=0:halt_on_error=1"}, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_temporary_short_string(self): self.run_case(0)
    def test_temporary_large_string(self): self.run_case(1)
    def test_temporary_unicode_string(self): self.run_case(2)
    def test_initialization_retries_after_invalid_string(self): self.run_case(3)
    def test_zero_tiny_and_full_diagnostic_buffers(self): self.run_case(4)
    def test_valid_vector_string_keeps_its_value(self): self.run_case(5)
    def test_other_invalid_return_keeps_shape_diagnostic(self): self.run_case(6)

    def test_vec2_input_init_update_and_commit(self): self.run_case(7)
    def test_vec2_out_of_band_initialization(self): self.run_case(8)
    def test_vec2_scalar_broadcast(self): self.run_case(9)
    def test_vec2_string_return(self): self.run_case(10)
    def test_vec2_missing_component_is_local_and_retryable(self): self.run_case(11)
    def test_vec2_nonfinite_return_is_local_and_retryable(self): self.run_case(12)
    def test_vec3_still_requires_third_component(self): self.run_case(13)
    def test_invalid_dimensions_do_not_access_or_write_buffers(self): self.run_case(14)
    def test_vector_stale_generation_rejected(self): self.run_case(15)
    def test_vec2_nonfinite_input_rejected(self): self.run_case(16)
