"""Exercise vendored numeric widths and rejection paths through the real C VM."""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
QUICKJS = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/QuickJSNG"

HARNESS = r'''
#include "quickjs.c"
#include <assert.h>

static size_t rejected_string_allocation;
static void *bounded_string_malloc(void *opaque, size_t size) {
    if (size > (size_t)JS_STRING_LEN_MAX) {
        rejected_string_allocation = size;
        return NULL;
    }
    return js_def_malloc(opaque, size);
}

static int realloc_calls, realloc_fail_after = -1;
static void *observed_realloc(void *opaque, void *ptr, size_t size) {
    realloc_calls++;
    if (realloc_fail_after == 0)
        return NULL;
    if (realloc_fail_after > 0)
        realloc_fail_after--;
    return js_def_realloc(opaque, ptr, size);
}

static void expect_range_error(JSContext *ctx, JSValue result) {
    assert(JS_IsException(result));
    JSValue error = JS_GetException(ctx);
    assert(JS_IsError(error));
    JSValue name = JS_GetPropertyStr(ctx, error, "name");
    const char *text = JS_ToCString(ctx, name);
    assert(text && !strcmp(text, "RangeError"));
    JS_FreeCString(ctx, text);
    JS_FreeValue(ctx, name);
    JS_FreeValue(ctx, error);
}

int main(int argc, char **argv) {
    assert(argc == 2);
    JSRuntime *rt = JS_NewRuntime();
    assert(rt);
    JS_SetMemoryLimit(rt, 32 * 1024 * 1024);
    JSContext *ctx = JS_NewContext(rt);
    assert(ctx);
    if (!strcmp(argv[1], "bounds")) {
        /* Rejections must happen before touching these deliberately tiny inputs. */
        expect_range_error(ctx, js_new_string8_len(ctx, "", SIZE_MAX));
        expect_range_error(ctx, js_new_string16_len(ctx, NULL, SIZE_MAX));
        expect_range_error(ctx, JS_Eval(ctx, "", SIZE_MAX, "bounds.js", 0));
        expect_range_error(ctx, JS_ParseJSON(ctx, "", SIZE_MAX, "bounds.json"));
        StringBuffer b;
        assert(string_buffer_init(ctx, &b, SIZE_MAX) < 0);
        expect_range_error(ctx, string_buffer_end(&b));
        /* A capacity hint may include quoted-string spare room. Clamp the
           actual allocation as well as the recorded capacity, without making
           a gigabyte allocation or hiding the boundary behind the budget. */
        JS_SetMemoryLimit(rt, SIZE_MAX);
        rt->mf.js_malloc = bounded_string_malloc;
        for (int wide = 0; wide <= 1; wide++) {
            rejected_string_allocation = 0;
            assert(string_buffer_init2(ctx, &b, (size_t)JS_STRING_LEN_MAX + 2, wide) < 0);
            assert(rejected_string_allocation == sizeof(JSMallocBlockHeader) +
                   sizeof(JSString) + ((size_t)JS_STRING_LEN_MAX << wide) + 1 - wide);
            assert(JS_IsException(string_buffer_end(&b)));
            JSValue error = JS_GetException(ctx);
            assert(JS_IsError(error));
            JS_FreeValue(ctx, error);
        }
        rt->mf.js_malloc = js_def_malloc;
        JS_SetMemoryLimit(rt, 32 * 1024 * 1024);
        assert(string_buffer_init(ctx, &b, 8) == 0);
        assert(string_buffer_putc8(&b, 'x') == 0);
        assert(string_buffer_write8(&b, NULL, SIZE_MAX) < 0);
        expect_range_error(ctx, string_buffer_end(&b));
        assert(string_buffer_init(ctx, &b, 8) == 0);
        assert(string_buffer_write16(&b, NULL, SIZE_MAX) < 0);
        expect_range_error(ctx, string_buffer_end(&b));
        /* Observe the actual allocator boundary without a gigabyte allocation.
           A small request reaches it; the format cap must reject before it. */
        void *block = js_malloc(ctx, 4096);
        assert(block);
        rt->mf.js_realloc = observed_realloc;
        JS_SetMemoryLimit(rt, SIZE_MAX);
        realloc_fail_after = 0;
        realloc_calls = 0;
        assert(js_bytecode_realloc(ctx, block, (size_t)INT32_MAX / 2 + 1) == NULL);
        assert(realloc_calls == 0);
        realloc_fail_after = 0;
        assert(js_bytecode_realloc(ctx, block, 8192) == NULL);
        assert(realloc_calls > 0);
        rt->mf.js_realloc = js_def_realloc;
        realloc_fail_after = -1;
        js_free(ctx, block);
        JS_SetMemoryLimit(rt, 32 * 1024 * 1024);
        JSValue allocation_error = JS_GetException(ctx);
        assert(JS_IsError(allocation_error));
        JS_FreeValue(ctx, allocation_error);
        DynBuf code;
        dbuf_init2(&code, ctx, js_bytecode_realloc);
        assert(dbuf_putc(&code, 1) == 0);
        assert(dbuf_claim(&code, (size_t)INT32_MAX / 2 + 1) < 0);
        assert(code.size == 1 && dbuf_error(&code));
        dbuf_free(&code);
        /* The real compile owner must reject a failed source map, even when
           instruction encoding itself succeeded. Compare the accepted case. */
        for (int failed_map = 0; failed_map <= 1; failed_map++) {
            JSFunctionDef function = { 0 };
            function.ctx = ctx;
            function.home_object_var_idx = -1;
            function.this_active_func_var_idx = -1;
            function.new_target_var_idx = -1;
            function.this_var_idx = -1;
            dbuf_init2(&function.byte_code, ctx, js_bytecode_realloc);
            dbuf_init2(&function.pc2line, ctx, js_bytecode_realloc);
            function.pc2line.error = failed_map;
            assert(dbuf_putc(&function.byte_code, OP_return_undef) == 0);
            int status = resolve_labels(ctx, &function);
            assert(status == (failed_map ? -1 : 0));
            if (failed_map) {
                JSValue error = JS_GetException(ctx);
                assert(JS_IsError(error));
                JS_FreeValue(ctx, error);
            }
            dbuf_free(&function.byte_code);
            dbuf_free(&function.pc2line);
        }
        const uint16_t utf16[] = { 'A', 0x7f, 0x80, 0x7ff, 0x800, 0xd83d, 0xde00, 0xd800 };
        size_t bytes;
        assert(js_cstring_utf8_size(utf16, countof(utf16), false, &bytes) && bytes == 16);
        assert(js_cstring_utf8_size(utf16, countof(utf16), true, &bytes) && bytes == 18);
    } else if (!strcmp(argv[1], "compile-failures")) {
        int failures = 0, successes = 0, failures_after_dead_atom = 0;
        for (int fault = 0; fault < 20; fault++) {
            JSFunctionDef *fd = js_new_function_def(ctx, NULL, false, false, "failure.js", 1, 1);
            assert(fd);
            JSAtom saved = JS_NewAtom(ctx, "dynamic-live-atom-ownership-test");
            JSAtom dead = JS_NewAtom(ctx, "dynamic-dead-atom-ownership-test");
            dbuf_putc(&fd->byte_code, OP_push_atom_value);
            dbuf_put_u32(&fd->byte_code, JS_DupAtom(ctx, saved));
            dbuf_putc(&fd->byte_code, OP_drop);
            dbuf_putc(&fd->byte_code, OP_get_arg);
            dbuf_put_u16(&fd->byte_code, 0);
            dbuf_putc(&fd->byte_code, OP_if_false);
            dbuf_put_u32(&fd->byte_code, 0);
            dbuf_putc(&fd->byte_code, OP_return_undef);
            dbuf_putc(&fd->byte_code, OP_push_atom_value);
            size_t dead_operand = fd->byte_code.size;
            dbuf_put_u32(&fd->byte_code, JS_DupAtom(ctx, dead));
            dbuf_putc(&fd->byte_code, OP_drop);
            int label_pos = (int)fd->byte_code.size;
            dbuf_putc(&fd->byte_code, OP_label);
            dbuf_put_u32(&fd->byte_code, 0);
            for (int i = 0; i < 8192; i++) dbuf_putc(&fd->byte_code, OP_nop);
            dbuf_putc(&fd->byte_code, OP_return_undef);
            fd->label_slots = js_mallocz(ctx, sizeof(*fd->label_slots));
            assert(fd->label_slots);
            fd->label_count = fd->label_size = fd->jump_size = 1;
            fd->label_slots[0].ref_count = 1;
            fd->label_slots[0].pos = fd->label_slots[0].pos2 = label_pos;
            fd->label_slots[0].addr = -1;
            realloc_fail_after = fault;
            rt->mf.js_realloc = observed_realloc;
            int status = resolve_labels(ctx, fd);
            rt->mf.js_realloc = js_def_realloc;
            realloc_fail_after = -1;
            if (status < 0) {
                failures++;
                failures_after_dead_atom += get_u32(fd->byte_code.buf + dead_operand) == JS_ATOM_NULL;
                JSValue error = JS_GetException(ctx);
                assert(JS_IsError(error));
                JS_FreeValue(ctx, error);
            } else successes++;
            js_free_function_def(ctx, fd);
            const char *live_text = JS_AtomToCString(ctx, saved);
            const char *dead_text = JS_AtomToCString(ctx, dead);
            assert(live_text && !strcmp(live_text, "dynamic-live-atom-ownership-test"));
            assert(dead_text && !strcmp(dead_text, "dynamic-dead-atom-ownership-test"));
            JS_FreeCString(ctx, live_text);
            JS_FreeCString(ctx, dead_text);
            JS_FreeAtom(ctx, saved);
            JS_FreeAtom(ctx, dead);
        }
        fprintf(stdout, "compile failure cases: rejected=%d accepted=%d after-dead-atom=%d\n",
                failures, successes, failures_after_dead_atom);
        assert(failures > 0 && successes > 0 && failures_after_dead_atom > 0);
    } else {
        const char *source =
            "function check(v) { if (!v) throw Error('numeric boundary'); }"
            "for (const x of [0n,1n,-1n,2147483647n,2147483648n,4294967295n,"
            "4294967296n,9223372036854775807n,-9223372036854775808n,"
            "(1n<<200n)-1n]) {"
            " check(BigInt(x.toString())===x);"
            " for (const base of [2,8,16,36]) {"
            "  const s=x.toString(base), negative=s[0]==='-';let parsed=0n;"
            "  for(const digit of s.slice(negative?1:0)) {"
            "   const value='0123456789abcdefghijklmnopqrstuvwxyz'.indexOf(digit);"
            "   check(value>=0&&value<base);parsed=parsed*BigInt(base)+BigInt(value);"
            "  }check((negative?-parsed:parsed)===x);"
            " }"
            " for (const n of [1n,3n,4294967295n,4294967296n]) {"
            "  check((x/n)*n+x%n===x); check((x*n)/n===x);"
            " }"
            " for (const bits of [0,1,31,32,63,64,127,128,200]) {"
            "  const mask=(1n<<BigInt(bits))-1n;"
            "  check(BigInt.asUintN(bits,x)===(x&mask));"
            " }"
            "}"
            "for (const x of [Number.MIN_VALUE,Number.MAX_VALUE,Number.EPSILON,"
            "1e-308,1e308,4294967295,4294967296,9007199254740991,-2147483649]) {"
            " check(Number(x.toString())===x);"
            " check(JSON.parse(JSON.stringify(x))===x);"
            "}"
            "const s='\\u{1F600}e\\u0301\\uFB03';"
            "check(s.normalize('NFC')==='\\u{1F600}\\u00E9\\uFB03');"
            "check(s.normalize('NFKD')==='\\u{1F600}e\\u0301ffi');"
            "check('x'.repeat(100000).match(/^x{100000}$/)[0].length===100000);"
            "check(/(?<word>\\p{L}+)(\\d+)/u.exec('hello42').groups.word==='hello');"
            "check(/[\\q{ab|cd}]/v.test('cd'));"
            "const a=new Uint32Array([0,4294967295,4294967296]);"
            "check(a.join(',')==='0,4294967295,0');"
            "check(a.map(x=>x).filter(x=>x>0)[0]===4294967295);"
            "const ab=new ArrayBuffer(8,{maxByteLength:32});"
            "const view=new Uint8Array(ab);ab.resize(16);check(view.length===16);"
            "const seen=[];function Result(){return {}; }"
            "const result=Array.from.call(Result,{length:3,0:4,1:5,2:6},"
            " (value,index)=>{seen.push(index);return value+index;});"
            "check(result.length===3&&result[2]===8&&seen.join(',')==='0,1,2');";
        JSValue result = JS_Eval(ctx, source, strlen(source), "numeric.js", 0);
        if (JS_IsException(result)) {
            JSValue error = JS_GetException(ctx);
            const char *text = JS_ToCString(ctx, error);
            fprintf(stderr, "%s\n", text ? text : "missing exception");
            JS_FreeCString(ctx, text);
            JS_FreeValue(ctx, error);
            return 1;
        }
        JS_FreeValue(ctx, result);
    }
    JS_FreeContext(ctx);
    JS_FreeRuntime(rt);
    return 0;
}
'''


class QuickJSNumericBoundariesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-quickjs-numeric-")
        root = Path(cls.temporary.name)
        main = root / "main.c"
        main.write_text(HARNESS)
        cls.binary = root / "numeric"
        command = [
            shutil.which("clang"), "-std=c11", "-O1", "-I", str(QUICKJS),
            "-Wshorten-64-to-32", "-Wconditional-uninitialized",
            "-Wunreachable-code", "-Wcomma", "-Wpointer-sign", "-Werror",
            *(["-fsanitize=address", "-fno-omit-frame-pointer"]
              if os.environ.get("MWX_SCENE_QUICKJS_ASAN") == "1" else []),
            str(main), *(str(QUICKJS / name) for name in
                         ("dtoa.c", "libregexp.c", "libunicode.c")),
            "-lm", "-o", str(cls.binary),
        ]
        completed = subprocess.run(command, capture_output=True, text=True, cwd=ROOT)
        if completed.returncode:
            cls.temporary.cleanup()
            raise AssertionError(completed.stdout + completed.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def run_case(self, name):
        result = subprocess.run([str(self.binary), name], capture_output=True, text=True,
                                timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_oversize_lengths_reject_before_input_access(self):
        self.run_case("bounds")

    def test_numeric_unicode_regex_and_typed_array_behavior(self):
        self.run_case("values")

    def test_compile_failure_preserves_atom_ownership(self):
        self.run_case("compile-failures")
