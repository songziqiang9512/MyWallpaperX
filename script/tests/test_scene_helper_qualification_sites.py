from __future__ import annotations

import importlib.util
import io
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scene_helper_qualification_sites.py"
SPEC = importlib.util.spec_from_file_location("scene_helper_qualification_sites", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
TOOL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TOOL)


class _Completed:
    def __init__(self, stderr: str, returncode: int = 1) -> None:
        self.stderr = stderr
        self.returncode = returncode


class QualificationSiteParsingTests(unittest.TestCase):
    def test_unresolved_sites_are_parsed_per_file_and_line(self) -> None:
        sets = [("fixture", [Path("/tmp/One.swift")], "import Foundation\n")]
        stderr = (
            "/tmp/One.swift:12:41: error: cannot find 'matches' in scope\n"
            "/tmp/One.swift:20:9: error: cannot find 'capture' in scope\n"
            "/tmp/One.swift:30:1: error: use of unresolved identifier 'other'\n"
        )
        with patch.object(TOOL.subprocess, "run", return_value=_Completed(stderr)):
            sites = TOOL.unresolved_sites(["matches", "capture"], sets)

        self.assertEqual(
            ["/tmp/One.swift:12:matches", "/tmp/One.swift:20:capture"],
            sites,
        )

    def test_unrelated_diagnostics_are_ignored(self) -> None:
        sets = [("fixture", [Path("/tmp/One.swift")], "import Foundation\n")]
        stderr = (
            "/tmp/One.swift:5:3: warning: variable 'matches' was never used\n"
            "/tmp/One.swift:7:1: error: cannot find 'unrelated' in scope\n"
        )
        with patch.object(TOOL.subprocess, "run", return_value=_Completed(stderr)):
            sites = TOOL.unresolved_sites(["matches"], sets)

        self.assertEqual([], sites)

    def test_harness_sets_require_a_family_source(self) -> None:
        # A family that no harness compiles yields no sets, which main() reports as blocked.
        # Emptying the search root keeps this a pure plumbing check.
        import tempfile

        with tempfile.TemporaryDirectory() as directory:
            with patch.object(TOOL, "TESTS_ROOT", Path(directory)):
                sets = TOOL.harness_sets(("Compilation/DoesNotExist",))
        self.assertEqual([], sets)

    def test_main_reports_zero_sites_for_a_name_that_is_defined(self) -> None:
        arguments = TOOL.argparse.Namespace(name=["mwxNoSuchHelper"], family=["Compilation/ShaderContract"])
        stdout = io.StringIO()
        with (
            patch.object(TOOL, "parse_arguments", return_value=arguments),
            patch.object(TOOL, "harness_sets", return_value=[("fixture", [Path("/tmp/One.swift")], "import Foundation\n")]),
            patch.object(TOOL, "unresolved_sites", return_value=[]),
            patch("sys.stdout", stdout),
        ):
            result = TOOL.main()

        self.assertEqual(0, result)
        self.assertIn("unresolved sites: 0", stdout.getvalue())


if __name__ == "__main__":
    unittest.main()
