from __future__ import annotations

import importlib.util
import io
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scene_helper_qualification_sites.py"
SPEC = importlib.util.spec_from_file_location("scene_helper_qualification_sites", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
TOOL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TOOL)


class _Completed:
    def __init__(self, stderr: str, stdout: str = "", returncode: int = 1) -> None:
        self.stderr = stderr
        self.stdout = stdout
        self.returncode = returncode


class QualificationParsingTests(unittest.TestCase):
    def test_scan_sites_accepts_both_diagnostic_shapes(self) -> None:
        sets = [("fixture", [Path("/tmp/One.swift")], "import Foundation\n")]
        stderr = (
            "/tmp/One.swift:12:41: error: cannot find 'matches' in scope\n"
            "/tmp/One.swift:20:9: error: use of local variable 'capture' before its declaration\n"
            "/tmp/One.swift:30:1: error: use of unresolved identifier 'other'\n"
        )
        with patch.object(TOOL.subprocess, "run", return_value=_Completed(stderr)):
            records, failures = TOOL.scan_sites(["matches", "capture"], sets)

        self.assertEqual(
            [
                ("/tmp/One.swift", 12, 41, "matches"),
                ("/tmp/One.swift", 20, 9, "capture"),
            ],
            records,
        )
        self.assertEqual([], failures)

    def test_unresolved_sites_keep_the_display_format(self) -> None:
        sets = [("fixture", [Path("/tmp/One.swift")], "import Foundation\n")]
        stderr = "/tmp/One.swift:12:41: error: cannot find 'matches' in scope\n"
        with patch.object(TOOL.subprocess, "run", return_value=_Completed(stderr)):
            display = TOOL.unresolved_sites(["matches"], sets)

        self.assertEqual(["/tmp/One.swift:12:matches"], display)


class QualificationRewriteTests(unittest.TestCase):
    def _qualify(self, text: str, line: int, column: int = 1, name: str = "matches") -> tuple[bool, str]:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Fixture.swift"
            path.write_text(text, encoding="utf-8")
            result = TOOL.qualify(str(path), line, column, name, "Facts")
            return result, path.read_text(encoding="utf-8")

    def test_qualify_rewrites_only_the_call(self) -> None:
        text = "let a = matches(pattern, in: source)\nlet b = matches.count\n"
        result, updated = self._qualify(text, 1)

        self.assertTrue(result)
        self.assertEqual(
            "let a = Facts.matches(pattern, in: source)\nlet b = matches.count\n", updated
        )

    def test_qualify_searches_nearby_lines_for_multi_line_calls(self) -> None:
        text = "let found = matches(\n    pattern,\n    in: source\n)\n"
        result, updated = self._qualify(text, 3)

        self.assertTrue(result)
        self.assertTrue(updated.startswith("let found = Facts.matches("))

    def test_qualify_leaves_an_already_qualified_site_alone(self) -> None:
        text = "let a = Facts.matches(pattern, in: source)\n"
        result, updated = self._qualify(text, 1)

        self.assertFalse(result)
        self.assertEqual(text, updated)

    def test_qualify_ignores_local_variable_uses(self) -> None:
        text = "let matches = 3\nlet total = matches + 1\n"
        result, updated = self._qualify(text, 2)

        self.assertFalse(result)
        self.assertEqual(text, updated)

    def test_qualify_reports_a_miss_when_no_call_is_in_range(self) -> None:
        text = "".join(f"let value{index} = {index}\n" for index in range(20))
        result, _ = self._qualify(text, 10)

        self.assertFalse(result)


class BracePostConditionTests(unittest.TestCase):
    def test_brace_delta_flags_a_lost_structural_brace(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Fixture.swift"
            path.write_text("enum E {\n    func f() {\n    }\n", encoding="utf-8")
            committed = _Completed("", "enum E {\n    func f() {\n    }\n}\n", returncode=0)
            with patch.object(TOOL.subprocess, "run", return_value=committed):
                problems = TOOL.brace_delta_report([str(path)], "HEAD")

        self.assertEqual(1, len(problems))
        self.assertIn("brace deficit changed", problems[0])

    def test_brace_delta_accepts_a_balanced_removal(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Fixture.swift"
            path.write_text("enum E {\n}\n", encoding="utf-8")
            committed = _Completed("", "enum E {\n    func f() {\n    }\n}\n", returncode=0)
            with patch.object(TOOL.subprocess, "run", return_value=committed):
                problems = TOOL.brace_delta_report([str(path)], "HEAD")

        self.assertEqual([], problems)


class HarnessSetReportingTests(unittest.TestCase):
    def test_skipped_sets_report_their_reason(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "test_fixture.py").write_text(
                "import missing_dependency_xyz\nSWIFT_SOURCES = []\n", encoding="utf-8"
            )
            with patch.object(TOOL, "TESTS_ROOT", root):
                sets, skipped = TOOL.harness_sets(("Compilation/Anything",))

        self.assertEqual([], sets)
        self.assertEqual(1, len(skipped))
        self.assertIn("import failed", skipped[0][1])

    def test_empty_sets_are_skipped_with_a_reason(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "test_fixture.py").write_text(
                "SWIFT_SOURCES = []  # Compilation/ShaderPreparation family\n", encoding="utf-8"
            )
            with patch.object(TOOL, "TESTS_ROOT", root):
                sets, skipped = TOOL.harness_sets(("Compilation/ShaderPreparation",))

        self.assertEqual([], sets)
        self.assertEqual([("test_fixture", "empty SWIFT_SOURCES")], skipped)


class MainModeTests(unittest.TestCase):
    def test_brace_delta_mode_reports_problems(self) -> None:
        arguments = TOOL.argparse.Namespace(
            name=["matches"],
            family=[],
            apply=False,
            qualified_with="Facts",
            brace_delta=["Fixture.swift"],
            base_ref="HEAD",
        )
        with (
            patch.object(TOOL, "parse_arguments", return_value=arguments),
            patch.object(TOOL, "brace_delta_report", return_value=["Fixture.swift: missing"]),
            patch("sys.stderr", io.StringIO()),
        ):
            result = TOOL.main()

        self.assertEqual(1, result)

    def test_apply_mode_reports_unresolved_sites(self) -> None:
        arguments = TOOL.argparse.Namespace(
            name=["matches"],
            family=[],
            apply=True,
            qualified_with="Facts",
            brace_delta=[],
            base_ref="HEAD",
        )
        with (
            patch.object(TOOL, "parse_arguments", return_value=arguments),
            patch.object(TOOL, "harness_sets", return_value=([("fixture", [Path("/tmp/One.swift")], "")], [])),
            patch.object(TOOL, "apply_qualifications", return_value=(3, ["/tmp/One.swift:12:1:matches"])),
            patch("sys.stdout", io.StringIO()),
            patch("sys.stderr", io.StringIO()),
        ):
            result = TOOL.main()

        self.assertEqual(1, result)


if __name__ == "__main__":
    unittest.main()
