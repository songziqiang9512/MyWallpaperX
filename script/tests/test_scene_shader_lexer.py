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


if __name__ == "__main__":
    unittest.main()
