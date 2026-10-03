"""Behavioral fixtures for the lexical dependency policy (not product tests)."""
from __future__ import annotations

import copy
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from script import check_scene_dependencies as checker


def configuration():
    return {
        "schema_version": 1, "source_root": "Product", "test_root": "script/tests",
        "rule": {"id": "one-edge", "consumer": "Rendering", "target": "Compilation",
                 "owner": "test-owner", "retirement": "when replaced"},
        "public_contracts": {"Prepared": "immutable prepared value"}, "todo": [],
    }


def sources(consumer="let value: Prepared"):
    return {
        "Product/Compilation/Values.swift": "nonisolated struct Prepared {}\nprivate enum Parser {}",
        "Product/Rendering/Draw.swift": consumer,
    }


def acknowledge(config, report):
    config["todo"] = [
        {**{k: edge[k] for k in ("rule", "consumer", "symbol")},
         "owner": "test-owner", "reason": "existing", "retirement": "remove edge"}
        for edge in report["violations"]
    ]


class DependencyPolicyTests(unittest.TestCase):
    def test_prepared_contract_allowed_internal_type_forbidden_in_same_file(self):
        config = configuration()
        report = checker.scan(sources("let value: Prepared\nlet parser = Parser()"), config)
        self.assertEqual([e["symbol"] for e in report["violations"]], ["Parser"])
        self.assertEqual(report["violations"][0]["line"], 2)
        self.assertEqual(len(checker.compare(config, report)["new"]), 1)

    def test_new_internal_declaration_is_forbidden_without_name_list_update(self):
        tree = sources("let compiler = NewCompiler()")
        tree["Product/Compilation/New.swift"] = "final class NewCompiler {}"
        self.assertEqual(checker.scan(tree, configuration())["violations"][0]["symbol"], "NewCompiler")

    def test_unicode_and_raw_identifiers_cannot_hide_new_internal_edges(self):
        for declaration, consumer, symbol in (
            ('enum 编译器 {}', 'let a = 编译器()', '编译器'),
            ('struct 🛠 {}', 'let a = 🛠()', '🛠'),
            ('struct Cafe\u0301 {}', 'let a = Cafe\u0301()', 'Cafe\u0301'),
            ('enum `class` {}', 'let a = `class`()', 'class'),
            ('enum `raw type` {}', 'let a = `raw type`()', 'raw type'),
            ('enum `带"符号` {}', 'let a = `带"符号`()', '带"符号'),
        ):
            tree = sources(consumer)
            tree['Product/Compilation/Unicode.swift'] = declaration
            tree['script/tests/embedded.py'] = 'HARNESS = ' + repr(consumer)
            report = checker.scan(tree, configuration())
            self.assertEqual([x['symbol'] for x in report['violations']], [symbol])
            self.assertEqual([x['symbol'] for x in report['harness_consumers']], [symbol])

    def test_raw_and_plain_identifiers_share_one_identity(self):
        tree = sources('let a: `Prepared`\nlet b: Prepared')
        self.assertEqual(len(checker.scan(tree, configuration())['edges']), 1)

    def test_unsupported_declarations_and_unterminated_raw_names_fail_closed(self):
        for text in ('enum {}', 'struct', 'struct `missing {}'):
            with self.assertRaisesRegex(ValueError, 'unsupported'):
                checker.declared_types(text)

    def test_comments_strings_raw_multiline_and_nested_comments_are_ignored(self):
        swift = '''// Parser
/* Parser /* Parser */ Parser */
let a = "Parser"
let b = #"Parser"#
let c = """Parser
Parser"""
let d = ##"Parser \\##(Parser())"##
let value: Prepared
'''
        self.assertEqual(checker.scan(sources(swift), configuration())["violations"], [])
        masked = checker.mask_swift(swift)
        self.assertEqual(len(masked), len(swift))
        self.assertEqual(masked.count("\n"), swift.count("\n"))

    def test_nested_types_are_not_mistaken_for_global_types(self):
        declarations = checker.declared_types('struct Top { enum Nested {} }\nextension Top { struct Added {} }\ntypealias Alias = Top')
        self.assertEqual(declarations, {"Top", "Alias"})

    def test_file_type_edge_deduplicated_and_explicit_alias_counted(self):
        report = checker.scan(sources("typealias Local = Parser\nlet a = Parser()\nlet b: Parser"), configuration())
        self.assertEqual(len(report["violations"]), 1)

    def test_other_product_directories_are_reported_without_expanding_pilot(self):
        tree = sources()
        tree["Product/Systems/Prepare.swift"] = "let parser = Parser()"
        report = checker.scan(tree, configuration())
        self.assertEqual(report["violations"], [])
        self.assertTrue(any(x["symbol"] == "Parser" for x in report["edges"]))

    def test_real_swift_and_python_embedded_harness_are_consumers_not_exemptions(self):
        tree = sources()
        tree["script/tests/Fixture.swift"] = "let a = Parser()"
        tree["script/tests/test_compiler.py"] = 'SOURCE = "Parser.swift"\nHARNESS = """import Foundation\nlet a = Parser()"""\n'
        report = checker.scan(tree, configuration())
        self.assertEqual(len(report["harness_consumers"]), 2)
        self.assertEqual(report["harness_files"], 2)
        self.assertEqual(report["violations"], [])
        self.assertTrue(all(not x["public_contract"] for x in report["harness_consumers"]))
        self.assertEqual(next(x for x in report["harness_consumers"] if x["consumer"].endswith(".py"))["line"], 2)

    def test_stale_todo_is_red_then_ratchet_removes_it(self):
        config = configuration()
        acknowledge(config, checker.scan(sources("let p = Parser()"), config))
        report = checker.scan(sources(), config)
        self.assertEqual(len(checker.compare(config, report)["stale"]), 1)
        updated = checker.ratchet(config, report, "prepared contract replaced parser")
        self.assertEqual(updated["todo"], [])
        self.assertEqual(len(updated["last_ratchet"]["removed"]), 1)

    def test_ratchet_never_accepts_growth_even_with_reason(self):
        config = configuration()
        report = checker.scan(sources("let p = Parser()"), config)
        with self.assertRaisesRegex(ValueError, "refuses"):
            checker.ratchet(config, report, "want more")
        with self.assertRaisesRegex(ValueError, "requires"):
            checker.ratchet(config, report, "")

    def test_new_consumer_of_existing_todo_type_is_red(self):
        config = configuration()
        tree = sources("let p = Parser()")
        acknowledge(config, checker.scan(tree, config))
        tree["Product/Rendering/New.swift"] = "let p = Parser()"
        self.assertEqual(len(checker.compare(config, checker.scan(tree, config))["new"]), 1)

    def test_base_ref_rejects_manual_todo_growth_allowance_and_scope_changes(self):
        previous = configuration()
        current = copy.deepcopy(previous)
        report = checker.scan(sources("let p = Parser()"), current)
        acknowledge(current, report)
        self.assertIn("todo baseline expanded relative to base ref", checker.compare(current, report, previous)["errors"])
        current["public_contracts"]["Parser"] = "unjustified"
        current["source_root"] = "Elsewhere"
        errors = checker.compare(current, report, previous)["errors"]
        self.assertEqual(len(errors), 3)

    def test_missing_public_declaration_and_duplicate_declaration_fail_closed(self):
        with self.assertRaisesRegex(ValueError, "lack declarations"):
            checker.scan({}, configuration())
        tree = sources()
        tree["Product/Compilation/Other.swift"] = "struct Prepared {}"
        with self.assertRaisesRegex(ValueError, "ambiguous"):
            checker.scan(tree, configuration())

    def test_invalid_harness_python_is_not_silently_omitted(self):
        tree = sources()
        tree["script/tests/broken.py"] = "def :"
        with self.assertRaises(SyntaxError):
            checker.scan(tree, configuration())

    def test_duplicate_or_unowned_todo_rejected(self):
        config = configuration()
        acknowledge(config, checker.scan(sources("let p = Parser()"), config))
        checker.validate_config(config)
        config["todo"].append(copy.deepcopy(config["todo"][0]))
        with self.assertRaisesRegex(ValueError, "duplicate"):
            checker.validate_config(config)
        config["todo"].pop()
        del config["todo"][0]["owner"]
        with self.assertRaisesRegex(ValueError, "owner"):
            checker.validate_config(config)


class DependencyCLITests(unittest.TestCase):
    def test_git_visible_untracked_new_edge_is_red_and_git_base_cannot_be_forged(self):
        with tempfile.TemporaryDirectory(prefix="scene-dependency-tests-") as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", directory], check=True)
            config = configuration()
            for relative, text in {**sources(), checker.BASELINE: json.dumps(config)}.items():
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)
            def run(*args):
                with patch.object(checker, "ROOT", root), patch("sys.argv", ["checker", *args]), patch("builtins.print"):
                    return checker.main()
            self.assertEqual(run("--check"), 0)
            (root / "Product/Rendering/New.swift").write_text("let p = Parser()")
            self.assertEqual(run("--check"), 1)
            self.assertEqual(run("--audit"), 0)
            self.assertEqual(run("--ratchet-baseline", "--reason", "no"), 2)
            self.assertEqual(run("--base-ref", "no-such-ref"), 2)


if __name__ == "__main__":
    unittest.main()
