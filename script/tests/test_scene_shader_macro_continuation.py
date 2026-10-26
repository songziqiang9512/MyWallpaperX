"""Function macro continuation through the real graph and preprocessor owners."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_scene_shader_preprocessor import REPO_ROOT, SWIFT_SOURCES


HARNESS = REPO_ROOT / "script/tests/fixtures/SceneShaderMacroContinuationChecks.swift"
DEFINITION = "#define USER_FN(x) ((x) + 1.0)\n"


def cases():
    result = []

    def add(name, source, *, path="shaders/main.frag", files=None, limits=None):
        result.append(dict(name=name, root=path, files={path: source, **(files or {})},
                           limits=limits or {}))

    add("same", DEFINITION + "float result = USER_FN(2.0);")
    add("split-name", DEFINITION + "float result = USER_FN\n(2.0);")
    add("split-argument", DEFINITION + "float result = USER_FN(\n2.0);")
    add("all-split", DEFINITION + "float result = USER_FN\n(\n2.0\n);")
    add("renamed-resource", DEFINITION.replace("USER_FN", "RENAMED_FN")
        + "float result = RENAMED_FN\n(2.0);", path="shaders/other/renamed.frag")
    add("alias", DEFINITION + "#define FN_ALIAS USER_FN\nfloat result = FN_ALIAS\n(2.0);")
    add("nested", DEFINITION + "#define OUTER(x) USER_FN(x)\n"
        + "float result = OUTER\n(USER_FN\n(1.0));")
    add("zero-parameter", "#define ZERO() 7.0\nfloat result = ZERO\n();")
    add("block-comment", DEFINITION + "float result = USER_FN /* gap */ (2.0);")
    add("line-comment", DEFINITION + "float result = USER_FN // gap\n(2.0);")
    add("unicode-comment", DEFINITION + "float result = USER_FN /*e\u0301👩‍🚀*/\n(2.0);")
    add("long-comment", DEFINITION + "float result = USER_FN /*" + "x" * 8192 + "*/\n(2.0);")
    add("blank-lines", DEFINITION + "float result = USER_FN\n\n\n(2.0);")
    add("equivalent-expression", DEFINITION + "float result = USER_FN\n((1.0 + 1.0));")
    add("identifier-boundary", "#define TY(x) x\nTY(float)u_Value;")
    add("empty-token-boundary", "#define EMPTY()\nfloat result = a+EMPTY()+b;")
    add("original-tokens", "#define ID(x) x\nfloat original = 1e-3;\n"
        + "i++; j--; i += 2; bool both = a && b;\nfloat expanded = ID(1e-3);")
    add("bare", DEFINITION + "float result = USER_FN;")
    add("bare-eof", DEFINITION + "USER_FN")
    add("not-call", DEFINITION + "float result = USER_FN\n+2.0;")
    add("unknown", DEFINITION + "float result = UNKNOWN_FN\n(2.0);")
    add("protected", DEFINITION
        + '// USER_FN\n// (2.0)\nconst char* label = "USER_FN(2.0)";')
    add("inactive", DEFINITION + "#if 0\nUSER_FN(\n#endif\nfloat sentinel = 3.0;")
    add("undef-boundary", DEFINITION + "USER_FN\n#undef USER_FN\n"
        + "#define USER_FN(x) ((x) + 2.0)\n;\nfloat result = USER_FN\n(2.0);")
    add("include-boundary", DEFINITION + 'USER_FN\n#include "tail.glsl"',
        files={"shaders/tail.glsl": ";\nfloat result = USER_FN\n(2.0);"})
    add("condition-boundary", DEFINITION + "USER_FN\n#if 1\n;\n"
        + "float result = USER_FN\n(2.0);\n#endif")
    for kind, directive, files in [
        ("define", "#define OTHER 1", {}),
        ("include", '#include "tail.glsl"', {"shaders/tail.glsl": "2.0);"}),
        ("condition", "#if 1\n2.0);\n#endif", {}),
    ]:
        add("incomplete-before-" + kind, DEFINITION + "float result = USER_FN(\n"
            + directive, files=files)
    add("metadata", DEFINITION + "// heading\nfloat result = USER_FN\n(2.0);\n"
        + 'uniform float u_Level; // [COMBO] {"combo":"LEVEL","default":2}')
    add("span-annotation", DEFINITION
        + 'float result = USER_FN // [COMBO] {"combo":"SPAN","default":1}\n'
        + "(2.0);\nuniform float u_Tail;")
    add("included-metadata", DEFINITION + '#include "declaration.glsl"\n'
        + "float result = USER_FN\n(2.0);",
        files={"shaders/declaration.glsl":
               'uniform float u_Included; // [COMBO] {"combo":"INCLUDED","default":1}'})
    add("unterminated", DEFINITION + "float result = USER_FN(2.0;")
    add("arity", DEFINITION + "float result = USER_FN\n(1.0, 2.0);")
    add("empty-argument", DEFINITION + "float result = USER_FN\n();")
    add("recursive", "#define LOOP(x) LOOP(x)\nfloat result = LOOP\n(1.0);")
    add("variadic", "#define BAD(...) 1\nfloat result = 1;")
    add("input-budget", DEFINITION + "float result = USER_FN\n" + "\n" * 100 + "(2.0);",
        limits={"maximumInputBytes": 64})
    add("line-budget", DEFINITION + "float result = USER_FN\n(2.0);",
        limits={"maximumOutputLines": 1})
    add("pending-line-budget", DEFINITION + "float result = USER_FN\n\n\n\n"
        + 'uniform sampler2D g_Texture0; // {"default": }',
        limits={"maximumOutputLines": 2})
    repeated = "#define DUP(x) ((x)+(x)+(x)+(x)+(x)+(x)+(x)+(x))\n"
    for name, limits in [("token-budget", {"maximumMacroExpansionTokens": 8}),
                         ("byte-budget", {"maximumMacroExpansionBytes": 32})]:
        add(name, repeated + "float result = DUP\n(2.0);", limits=limits)
    add("depth-budget", "#define FIRST(x) SECOND(x)\n#define SECOND(x) x\n"
        + "float result = FIRST\n(2.0);", limits={"maximumMacroExpansionDepth": 1})
    return result


class SceneShaderMacroContinuationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        swiftc = shutil.which("swiftc")
        if not swiftc:
            raise unittest.SkipTest("swiftc unavailable")
        cls.temporary = tempfile.TemporaryDirectory(prefix="shader-macro-continuation-")
        cls.addClassCleanup(cls.temporary.cleanup)
        work = Path(cls.temporary.name)
        evidence = os.environ.get("MWX_MACRO_CONTINUATION_EVIDENCE")
        cls.evidence = Path(evidence) if evidence else None
        if cls.evidence:
            cls.evidence.mkdir(parents=True, exist_ok=True)
        snapshot = os.environ.get("MWX_MACRO_CONTINUATION_SOURCE_SNAPSHOT")
        sources = [Path(snapshot) / p.relative_to(REPO_ROOT) if snapshot else p
                   for p in SWIFT_SOURCES]
        missing = [str(p) for p in sources if not p.is_file()]
        if missing:
            raise AssertionError(f"Incomplete real source closure: {missing}")
        binary = work / "probe"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(work / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(work / "cache")
        command = [swiftc, "-parse-as-library", "-module-cache-path", str(work / "cache"),
                   *(str(p) for p in sources), str(HARNESS), "-o", str(binary)]
        compiled = subprocess.run(command, cwd=REPO_ROOT, capture_output=True, text=True,
                                  timeout=120, env=environment)
        cls.retain("compile-command.json", json.dumps(command, indent=2))
        cls.retain("compile.stdout", compiled.stdout)
        cls.retain("compile.stderr", compiled.stderr)
        if compiled.returncode:
            raise AssertionError(compiled.stdout + compiled.stderr)
        input_path = work / "input.json"
        payload = json.dumps(cases(), indent=2)
        input_path.write_text(payload)
        cls.retain("cases.json", payload)
        executed = subprocess.run([str(binary), str(input_path), str(work / "fixtures")],
                                  cwd=REPO_ROOT, capture_output=True, text=True, timeout=30,
                                  env=environment)
        cls.retain("process.stdout", executed.stdout)
        cls.retain("process.stderr", executed.stderr)
        if executed.returncode:
            raise AssertionError(executed.stdout + executed.stderr)
        report = json.loads(executed.stdout)
        cls.retain("observations.json", json.dumps(report, indent=2))
        cls.rows = {row["name"]: row for row in report["rows"]}

    @classmethod
    def retain(cls, name, contents):
        if cls.evidence:
            (cls.evidence / name).write_text(contents)

    def code(self, name):
        row = self.rows[name]
        self.assertEqual(row["status"], "success", row)
        return "".join(row["code"].split())

    def test_equivalent_calls_expand_across_lines_aliases_and_comment_whitespace(self):
        expected = "floatresult=((2.0)+1.0);"
        for name in ["same", "split-name", "split-argument", "all-split", "renamed-resource",
                     "alias", "block-comment", "line-comment", "blank-lines"]:
            with self.subTest(name=name):
                self.assertEqual(self.code(name), expected)
        self.assertEqual(self.code("nested"), "floatresult=((((1.0)+1.0))+1.0);")
        self.assertEqual(self.code("zero-parameter"), "floatresult=7.0;")
        self.assertEqual(self.code("equivalent-expression"), "floatresult=(((1.0+1.0))+1.0);")

    def test_unicode_and_long_comment_keep_expansion_and_physical_lines(self):
        for name, comment in (("unicode-comment", "/*e\u0301👩‍🚀*/"),
                              ("long-comment", "/*" + "x" * 8192 + "*/")):
            with self.subTest(case=name):
                self.assertEqual(self.code(name), "floatresult=((2.0)+1.0);")
                self.assertIn(comment, self.rows[name]["source"])
                self.assertEqual([item["sourceLine"] for item in self.rows[name]["sourceMap"]], [2, 3])

    def test_bare_unknown_inactive_and_protected_neighbors(self):
        self.assertEqual(self.code("bare"), "floatresult=USER_FN;")
        self.assertEqual(self.code("bare-eof"), "USER_FN")
        self.assertEqual(self.code("not-call"), "floatresult=USER_FN+2.0;")
        self.assertEqual(self.code("unknown"), "floatresult=UNKNOWN_FN(2.0);")
        self.assertEqual(self.code("inactive"), "floatsentinel=3.0;")
        self.assertEqual(self.rows["protected"]["source"],
                         '// USER_FN\n// (2.0)\nconst char* label = "USER_FN(2.0)";')

    def test_replacements_keep_token_boundaries_without_splitting_original_tokens(self):
        # Do not use code(), which removes whitespace and could hide a merge.
        identifier = self.rows["identifier-boundary"]
        self.assertEqual(identifier["status"], "success", identifier)
        self.assertRegex(identifier["source"], r"^float\s+u_Value;$")
        empty = self.rows["empty-token-boundary"]
        self.assertEqual(empty["status"], "success", empty)
        self.assertRegex(empty["source"], r"a\s*\+\s+\+\s*b")
        self.assertNotIn("++", empty["source"])
        original = self.rows["original-tokens"]
        self.assertEqual(original["status"], "success", original)
        source = original["source"]
        self.assertRegex(source, r"\bi\s*\+\+")
        self.assertRegex(source, r"\bj\s*--")
        self.assertIn("+=", source)
        self.assertIn("&&", source)
        self.assertEqual(source.count("1e-3"), 2)

    def test_directive_boundaries_keep_the_current_environment_and_include_owner(self):
        self.assertEqual(self.code("undef-boundary"), "USER_FN;floatresult=((2.0)+2.0);")
        for name in ["include-boundary", "condition-boundary"]:
            with self.subTest(name=name):
                self.assertEqual(self.code(name), "USER_FN;floatresult=((2.0)+1.0);")
        self.assertEqual(self.rows["include-boundary"]["dependencies"],
                         ["shaders/main.frag", "shaders/tail.glsl"])
        for name in ["incomplete-before-define", "incomplete-before-include",
                     "incomplete-before-condition"]:
            with self.subTest(name=name):
                self.assert_failure(name, "function-like-macro", line=2)

    def test_physical_source_map_and_active_metadata_survive_continuation(self):
        row = self.rows["metadata"]
        self.assertEqual(row["status"], "success", row)
        self.assertEqual([m["sourceLine"] for m in row["sourceMap"]], [2, 3, 4, 5])
        self.assertEqual([m["outputLine"] for m in row["sourceMap"]], [1, 2, 3, 4])
        self.assertEqual(row["declarations"], [dict(path="shaders/main.frag", line=5, name="u_Level")])
        self.assertEqual([(a["path"], a["line"]) for a in row["annotations"]],
                         [("shaders/main.frag", 5)])
        span = self.rows["span-annotation"]
        self.assertEqual(span["status"], "success", span)
        self.assertEqual([a["line"] for a in span["annotations"]], [2])
        self.assertEqual(span["declarations"], [dict(path="shaders/main.frag", line=4, name="u_Tail")])
        included = self.rows["included-metadata"]
        self.assertEqual(included["status"], "success", included)
        self.assertEqual(included["declarations"],
                         [dict(path="shaders/declaration.glsl", line=1, name="u_Included")])
        self.assertEqual([(a["path"], a["line"]) for a in included["annotations"]],
                         [("shaders/declaration.glsl", 1)])
        for name in ["metadata", "span-annotation", "included-metadata", "all-split"]:
            value = self.rows[name]
            self.assertEqual(len(value["source"].split("\n")), len(value["sourceMap"]), name)

    def assert_failure(self, name, code, line=None):
        row = self.rows[name]
        self.assertEqual(row["status"], "failure", row)
        self.assertEqual([d["code"] for d in row["diagnostics"]], [code], row)
        if line is not None:
            self.assertEqual(row["diagnostics"][0]["line"], line, row)

    def test_malformed_calls_and_expansion_resource_budgets_still_fail_closed(self):
        for name in ["unterminated", "arity", "empty-argument", "recursive", "variadic"]:
            with self.subTest(name=name):
                self.assert_failure(name, "function-like-macro")
        for name in ["input-budget", "line-budget", "pending-line-budget", "token-budget",
                     "byte-budget", "depth-budget"]:
            with self.subTest(name=name):
                self.assert_failure(name, "budget-exceeded")
        # The malformed sampler metadata is on line 6. Reject pending physical
        # lines before reaching that separate error, rather than only at flush.
        line = self.rows["pending-line-budget"]["diagnostics"][0]["line"]
        self.assertGreater(line, 0)
        self.assertLess(line, 6)


if __name__ == "__main__":
    unittest.main()
