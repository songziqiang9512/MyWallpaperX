from __future__ import annotations

from collections import Counter
from contextlib import redirect_stderr, redirect_stdout
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from script import check_test_assertions as gate


class TestAssertionGateTests(unittest.TestCase):
    def test_expression_census_preserves_operands_without_misclassifying_behavior(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = 'script/tests/test_example.py'
            (root / path).parent.mkdir(parents=True)
            (root / path).write_text('self.assertIn("slot.candidates.indices.reversed()", source)\n'
                                     'self.assertIn("ready", events)\n'
                                     'self.assertIn("func build(", source)\n')
            with patch.object(gate, 'test_paths', return_value=[path]):
                report = gate.expression_census(root)
            self.assertEqual(report['count'], 2)
            self.assertEqual([v['operand'] for v in report['entries']], ['source', 'events'])
            self.assertEqual(report['classification'], 'manual-provenance-review')

    def test_multiline_single_quotes_and_scope_are_detected(self) -> None:
        source = '''class Cases:
    async def test_declaration(self):
        self.assertIn(
            'func prepare(', source
        )
        self.assertNotIn("guard valid else", source)
'''
        found = gate.detect_source(source, "script/tests/test_fixture.py")
        self.assertEqual(sum(found.values()), 2)
        self.assertEqual({key[1] for key in found}, {"Cases.test_declaration"})

    def test_declared_boundary_excludes_expressions_and_other_assertions(self) -> None:
        source = '''self.assertIn("slot.candidates.indices.reversed()", source)
self.assertEqual("func prepare(", actual)
self.assertIn(prefix + "func prepare(", source)
self.assertIn("function", source)
self.assertIn(" guard valid else", source)
'''
        self.assertEqual(gate.detect_source(source, "script/tests/test_fixture.py"), Counter())

    def test_equal_count_replacement_is_growth(self) -> None:
        old = gate.detect_source('self.assertIn("func old(", source)', "script/tests/test_fixture.py")
        new = gate.detect_source('self.assertIn("func new(", source)', "script/tests/test_fixture.py")
        growth, reductions = gate.compare(new, old)
        self.assertEqual((len(growth), len(reductions)), (1, 1))

    def test_line_shift_preserves_identity_but_duplicate_addition_is_growth(self) -> None:
        source = 'self.assertIn("let value =", source)\n'
        old = gate.detect_source(source, "script/tests/test_fixture.py")
        self.assertEqual(old, gate.detect_source("\n\n" + source, "script/tests/test_fixture.py"))
        self.assertEqual(len(gate.compare(gate.detect_source(source * 2, "script/tests/test_fixture.py"), old)[0]), 1)

    def test_git_discovery_includes_untracked_tests_excludes_ignored_files(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            tests = root / "script/tests"
            tests.mkdir(parents=True)
            (root / ".gitignore").write_text("script/tests/test_ignored.py\n")
            for name in ("test_tracked.py", "test_new.py", "test_ignored.py", "support.py"):
                (tests / name).write_text('self.assertIn("var value =", source)\n')
            subprocess.run(["git", "add", "script/tests/test_tracked.py"], cwd=root, check=True)
            self.assertEqual(gate.test_paths(root), ["script/tests/test_new.py", "script/tests/test_tracked.py"])
            self.assertEqual(sum(gate.inventory(root).values()), 2)
            (tests / "test_tracked.py").unlink()
            self.assertEqual(gate.test_paths(root), ["script/tests/test_new.py"])

    def test_baseline_round_trip_and_detector_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "baseline.json"
            found = gate.detect_source('self.assertIn("struct Item", source)', "script/tests/test_fixture.py")
            value = gate.document(found)
            path.write_text(json.dumps(value))
            self.assertEqual(gate.load_baseline(path), found)
            value["detector"] = {"id": "broadened-without-review"}
            path.write_text(json.dumps(value))
            with self.assertRaises(ValueError):
                gate.load_baseline(path)

    def test_invalid_baseline_identity_and_duplicate_entries_fail_closed(self) -> None:
        found = gate.detect_source('self.assertIn("enum Case", source)', "script/tests/test_fixture.py")
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "baseline.json"
            for change in ("duplicate", "path", "count", "root"):
                with self.subTest(change=change):
                    value = gate.document(found)
                    if change == "duplicate":
                        value["entries"] *= 2
                    elif change == "path":
                        value["entries"][0]["path"] = "../test_elsewhere.py"
                    elif change == "count":
                        value["entries"][0]["count"] = True
                    else:
                        value = []
                    path.write_text(json.dumps(value))
                    with self.assertRaises(ValueError):
                        gate.load_baseline(path)

    def test_unparseable_test_source_is_not_silently_skipped(self) -> None:
        with self.assertRaises(SyntaxError):
            gate.detect_source("def invalid(:\n", "script/tests/test_fixture.py")

    def test_cli_requires_shrink_ratchet_and_never_accepts_growth(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "baseline.json"
            old = gate.detect_source('self.assertIn("class Old", source)', "script/tests/test_fixture.py")
            path.write_text(json.dumps(gate.document(old)))
            with patch.object(gate, "BASELINE", path), patch.object(gate, "baseline_at_ref", return_value=old), patch.object(gate, "inventory", return_value=Counter()), redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                self.assertEqual(gate.main([]), 1)
                self.assertEqual(gate.main(["--ratchet-baseline"]), 0)
                self.assertEqual(gate.load_baseline(path), Counter())
            before = path.read_bytes()
            with patch.object(gate, "BASELINE", path), patch.object(gate, "baseline_at_ref", return_value=old), patch.object(gate, "inventory", return_value=old), redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                self.assertEqual(gate.main(["--ratchet-baseline"]), 1)
            self.assertEqual(path.read_bytes(), before)

    def test_direct_baseline_growth_cannot_launder_new_assertion(self) -> None:
        original = gate.detect_source('self.assertIn("class Old", source)', "script/tests/test_fixture.py")
        replacement = gate.detect_source('self.assertIn("class New", source)', "script/tests/test_fixture.py")
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "baseline.json"
            path.write_text(json.dumps(gate.document(replacement)))
            before = path.read_bytes()
            with patch.object(gate, "BASELINE", path), patch.object(gate, "baseline_at_ref", return_value=original), patch.object(gate, "inventory", return_value=replacement), redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                self.assertEqual(gate.main(["--check"]), 1)
                self.assertEqual(gate.main(["--ratchet-baseline"]), 1)
            self.assertEqual(path.read_bytes(), before)

    def test_missing_committed_baseline_is_explicit_bootstrap(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "baseline.json"
            path.write_text(json.dumps(gate.document(Counter())))
            output = io.StringIO()
            with patch.object(gate, "BASELINE", path), patch.object(gate, "baseline_at_ref", return_value=None), patch.object(gate, "inventory", return_value=Counter()), redirect_stdout(output):
                self.assertEqual(gate.main([]), 0)
            self.assertTrue("BOOTSTRAP" in output.getvalue())

    def test_invalid_ref_and_malformed_committed_baseline_are_not_bootstrap(self) -> None:
        with patch.object(gate.subprocess, "run", side_effect=subprocess.CalledProcessError(128, ["git", "rev-parse"])):
            with self.assertRaises(subprocess.CalledProcessError):
                gate.baseline_at_ref(Path("."), "unknown-ref")
        results = [
            subprocess.CompletedProcess([], 0, stdout="a" * 40),
            subprocess.CompletedProcess([], 0, stdout=b"tracked baseline\0"),
            subprocess.CompletedProcess([], 0, stdout="invalid json"),
        ]
        with patch.object(gate.subprocess, "run", side_effect=results):
            with self.assertRaises(ValueError):
                gate.baseline_at_ref(Path("."), "HEAD")


if __name__ == "__main__":
    unittest.main()
