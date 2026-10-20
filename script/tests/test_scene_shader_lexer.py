#!/usr/bin/env python3
"""Exercise the product shader lexer through the shared frontend harness."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.scene_authored_shader_frontend_harness import AuthoredShaderFrontendHarness


class SceneShaderLexerTests(AuthoredShaderFrontendHarness, unittest.TestCase):
    def lex(self, sources):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "sources.json"
            path.write_text(json.dumps(sources), encoding="utf-8")
            result = subprocess.run(
                [str(self.binary), "--lex", str(path)], check=True,
                capture_output=True, text=True,
            )
        return json.loads(result.stdout)

    def test_lexer_ascii_identifier_boundaries(self):
        outputs = self.lex([chr(value) for value in range(128)])
        for value, output in enumerate(outputs):
            with self.subTest(value=value):
                expected = [chr(value)] if chr(value) in (
                    "_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
                ) else []
                self.assertEqual(
                    [token["text"] for token in output["tokens"]
                     if token["kind"] == "identifier"], expected,
                )

    def test_lexer_unicode_identifiers_and_diagnostic_positions(self):
        valid = ["变量_9", "δείγμα2", "échantillon", "𝒜_٢", "abc\u0301"]
        outputs = self.lex(valid + ["abc💡", "a\r\n@", "#define 中文_2 3\r\n中文_2"])
        for source, output in zip(valid, outputs):
            self.assertEqual(output["diagnostics"], [])
            self.assertEqual(output["tokens"], [
                {"kind": "identifier", "text": source, "line": 1, "column": 1}
            ])
        self.assertEqual(outputs[5]["tokens"][0]["text"], "abc")
        self.assertEqual(outputs[5]["diagnostics"], [
            {"code": "invalidToken", "line": 1, "column": 4}
        ])
        self.assertEqual(outputs[6]["diagnostics"], [
            {"code": "invalidToken", "line": 2, "column": 1}
        ])
        self.assertEqual(outputs[7]["defines"], {"中文_2": "3"})
        self.assertEqual(outputs[7]["diagnostics"], [])
        self.assertEqual(outputs[7]["tokens"][0]["line"], 2)

    def test_newlines_comments_and_directive_boundaries(self):
        source = "\n// 注释\n变量_2 /* comment */ + 3;\n\n"
        lf, crlf, cr = self.lex([
            source, source.replace("\n", "\r\n"), source.replace("\n", "\r"),
        ])
        self.assertEqual(lf, crlf)
        self.assertEqual(lf, cr)
        self.assertEqual(lf["source"], source)
        self.assertEqual(lf["diagnostics"], [])
        self.assertEqual(lf["tokens"][0], {
            "kind": "identifier", "text": "变量_2", "line": 3, "column": 1,
        })
        outputs = self.lex([
            "", "\n\n", "/* unterminated", "a\r\n@\rb",
            "// #define IGNORED 9\nIGNORED", "/* #version 150 */\na",
            "#define VALUE 3\r\nVALUE", "#version 150\na",
            "#define VALUE 1\n#define VALUE 2\nVALUE",
        ])
        self.assertEqual(outputs[0]["source"], "")
        self.assertEqual(outputs[1]["source"], "\n\n")
        self.assertEqual(outputs[2]["diagnostics"][0]["code"], "unterminatedComment")
        self.assertEqual(outputs[3]["source"], "a\n@\nb")
        self.assertEqual(outputs[3]["diagnostics"], [
            {"code": "invalidToken", "line": 2, "column": 1},
        ])
        for index in [4, 5]:
            self.assertEqual(outputs[index]["defines"], {})
        self.assertEqual(outputs[6]["defines"], {"VALUE": "3"})
        self.assertEqual(outputs[7]["diagnostics"][0]["code"], "unsupportedDirective")
        self.assertEqual(outputs[8]["diagnostics"][0]["code"], "malformedDefine")

    def test_original_source_and_token_budgets_still_apply(self):
        outputs = self.lex([
            " " * (512 * 1024), " " * (512 * 1024 + 1),
            "\r\n" * (256 * 1024) + " ",
            "; " * 100_000, "; " * 100_001,
        ])
        self.assertEqual(outputs[0]["diagnostics"], [])
        self.assertEqual(len(outputs[0]["source"]), 512 * 1024)
        for index in [1, 2]:
            self.assertEqual(outputs[index]["diagnostics"][0]["code"], "sourceTooLarge")
            self.assertIsNone(outputs[index]["source"])
        self.assertEqual(outputs[3]["diagnostics"], [])
        self.assertEqual(len(outputs[3]["tokens"]), 100_000)
        self.assertEqual(outputs[4]["diagnostics"][0]["code"], "tokenBudgetExceeded")


if __name__ == "__main__":
    unittest.main()
