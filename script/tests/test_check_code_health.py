from __future__ import annotations

import argparse
import copy
import importlib.util
import io
import json
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest.mock import patch


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "check_code_health.py"
SPEC = importlib.util.spec_from_file_location("check_code_health", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
GATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GATE)


def baseline() -> dict:
    return {"schemaVersion": 4, "hardLineLimit": 1000,
            "sourceRoots": ["MyWallpaperX", "WallpaperDaemonSources"]}


def git(root: Path, *arguments: str) -> str:
    return subprocess.run(["git", *arguments], cwd=root, check=True,
                          capture_output=True, text=True).stdout.strip()


class CodeHealthGateTests(unittest.TestCase):
    def test_one_ceiling_accepts_400_401_and_1000_without_warnings(self):
        counts = {f"MyWallpaperX/File{count}.swift": count for count in (0, 400, 401, 999, 1000)}
        self.assertEqual(GATE.current_tree_findings(baseline(), counts), [])
        counts["MyWallpaperX/New.swift"] = 1001
        self.assertEqual(GATE.current_tree_findings(baseline(), counts), [
            ("MyWallpaperX/New.swift", "file has 1001 lines; hard limit is 1000")])

    def test_growth_shrink_removal_and_new_family_files_need_no_lock_updates(self):
        for counts in ({"MyWallpaperX/Renderer+New.swift": 999},
                       {"MyWallpaperX/PreviouslyLocked.swift": 950},
                       {"MyWallpaperX/PreviouslyLocked.swift": 500}, {}):
            self.assertEqual(GATE.current_tree_findings(baseline(), counts), [])

    def test_schema_rejects_changed_ceiling_and_every_exception_mechanism(self):
        for ceiling in (True, None, 400, 999, 1001, 5000):
            value = baseline(); value["hardLineLimit"] = ceiling
            with self.subTest(ceiling=ceiling), self.assertRaises(ValueError):
                GATE.read_baseline_text(json.dumps(value), "fixture")
        for field in ("reviewLineLimit", "reviewWarningFiles", "legacyFiles", "graduatedFamilies", "lineLimit"):
            value = baseline(); value[field] = {}
            with self.subTest(field=field), self.assertRaises(ValueError):
                GATE.read_baseline_text(json.dumps(value), "fixture")
        for value in ([], None, {**baseline(), "schemaVersion": True},
                      {**baseline(), "schemaVersion": 5}):
            with self.subTest(value=value), self.assertRaises(ValueError):
                GATE.read_baseline_text(json.dumps(value), "fixture")

    def test_source_roots_are_exact_normalized_nonempty_unique_paths(self):
        for roots in ([], ["MyWallpaperX", "MyWallpaperX"], [None], [""],
                      ["/tmp/source"], ["../source"], ["MyWallpaperX/../Other"],
                      ["MyWallpaperX/"], ["."], ["MyWallpaperX/*"]):
            with self.subTest(roots=roots), self.assertRaises(ValueError):
                GATE.read_baseline_text(json.dumps({**baseline(), "sourceRoots": roots}), "fixture")
        self.assertTrue(GATE.belongs_to_source_root("MyWallpaperX/App/App.swift", baseline()["sourceRoots"]))
        self.assertFalse(GATE.belongs_to_source_root("MyWallpaperXBackup/File.swift", baseline()["sourceRoots"]))

    def test_authorized_schema_replacement_retires_old_locks_but_preserves_roots(self):
        for version in (1, 2, 3):
            old = {"schemaVersion": version, "sourceRoots": baseline()["sourceRoots"],
                   "legacyFiles": {"MyWallpaperX/Old.swift": 1200}}
            if version == 1:
                old["lineLimit"] = 400
            else:
                old.update(reviewLineLimit=400, hardLineLimit=800 if version == 2 else 1000)
            if version == 3:
                old.update(reviewWarningFiles={"MyWallpaperX/Locked.swift": 850},
                           graduatedFamilies={"renderer": {"maxLines": 400}})
            previous = GATE.read_baseline_text(json.dumps(old), "historical")
            self.assertEqual(GATE.historical_problems(baseline(), previous), [])
            with self.assertRaises(ValueError):
                GATE.current_tree_findings(previous, {})
            reduced = baseline(); reduced["sourceRoots"] = ["MyWallpaperX"]
            self.assertTrue(GATE.historical_problems(reduced, previous))

    def test_committed_unified_policy_cannot_raise_ceiling_or_restore_exceptions(self):
        previous = baseline()
        variants = [{**previous, "hardLineLimit": 1001},
                    {**previous, "legacyFiles": {"MyWallpaperX/Large.swift": 1200}},
                    {**previous, "sourceRoots": ["MyWallpaperX"]},
                    {**previous, "schemaVersion": 3}]
        for current in variants:
            self.assertTrue(GATE.historical_problems(current, previous))
        expanded = copy.deepcopy(previous); expanded["sourceRoots"].append("script/tests/fixtures")
        self.assertEqual(GATE.historical_problems(expanded, previous), [])

    def test_historical_schemas_cannot_be_used_as_current_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "baseline.json"
            path.write_text(json.dumps({"schemaVersion": 3, "hardLineLimit": 1000,
                                       "sourceRoots": ["MyWallpaperX"]}))
            with patch.object(GATE, "BASELINE_PATH", path), self.assertRaises(ValueError):
                GATE.load_current_baseline()

    def test_scan_includes_untracked_and_force_tracked_ignored_swift(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); git(root, "init", "--quiet")
            (root / "MyWallpaperX").mkdir(); (root / "WallpaperDaemonSources").mkdir()
            (root / ".gitignore").write_text("MyWallpaperX/Ignored*.swift\n")
            (root / "MyWallpaperX/Tracked.swift").write_text("line\n" * 1000)
            (root / "MyWallpaperX/New File.swift").write_text("line\n" * 1001)
            (root / "MyWallpaperX/Ignored.swift").write_text("line\n" * 2000)
            forced = root / "MyWallpaperX/IgnoredTracked.swift"
            forced.write_text("line\n" * 1001)
            deleted = root / "MyWallpaperX/Deleted.swift"; deleted.write_text("deleted\n")
            git(root, "add", "MyWallpaperX/Tracked.swift", "MyWallpaperX/Deleted.swift")
            git(root, "add", "-f", "MyWallpaperX/IgnoredTracked.swift")
            deleted.unlink()
            with patch.object(GATE, "REPO_ROOT", root):
                counts = GATE.swift_line_counts(baseline())
            self.assertEqual(counts, {"MyWallpaperX/IgnoredTracked.swift": 1001,
                                     "MyWallpaperX/New File.swift": 1001,
                                     "MyWallpaperX/Tracked.swift": 1000})
            self.assertEqual(len(GATE.current_tree_findings(baseline(), counts)), 2)

    def test_scan_rejects_missing_roots_unmanaged_sources_and_invalid_utf8(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); git(root, "init", "--quiet")
            with patch.object(GATE, "REPO_ROOT", root):
                with self.assertRaisesRegex(ValueError, "does not exist"):
                    GATE.swift_line_counts(baseline())
                (root / "MyWallpaperX").mkdir(); (root / "WallpaperDaemonSources").mkdir()
                outside = root / "Outside.swift"; outside.write_text("code")
                with self.assertRaisesRegex(ValueError, "outside configured"):
                    GATE.swift_line_counts(baseline())
                outside.unlink()
                (root / "MyWallpaperX/Bad.swift").write_bytes(b"\xff")
                with self.assertRaisesRegex(ValueError, "cannot read"):
                    GATE.swift_line_counts(baseline())

    def test_real_git_base_distinguishes_absence_invalid_ref_and_committed_raise(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); git(root, "init", "--quiet")
            git(root, "config", "user.name", "Code Health Fixture")
            git(root, "config", "user.email", "health@example.invalid")
            git(root, "commit", "--allow-empty", "--quiet", "-m", "before baseline")
            empty = git(root, "rev-parse", "HEAD")
            path = root / GATE.BASELINE_RELATIVE_PATH; path.parent.mkdir()
            path.write_text(json.dumps(baseline()))
            git(root, "add", str(GATE.BASELINE_RELATIVE_PATH))
            git(root, "commit", "--quiet", "-m", "unified policy")
            original = git(root, "rev-parse", "HEAD")
            path.write_text(json.dumps({**baseline(), "hardLineLimit": 1001}))
            git(root, "add", str(GATE.BASELINE_RELATIVE_PATH))
            git(root, "commit", "--quiet", "-m", "unauthorized increase")
            with patch.object(GATE, "REPO_ROOT", root):
                self.assertIsNone(GATE.baseline_at_ref(empty)[0])
                self.assertEqual(GATE.baseline_at_ref(original)[0], baseline())
                with self.assertRaisesRegex(ValueError, "not a commit"):
                    GATE.baseline_at_ref("missing-reference")
                with self.assertRaisesRegex(ValueError, "exactly 1000"):
                    GATE.baseline_at_ref("HEAD")

    def test_cli_has_no_ratchet_write_mode(self):
        with patch("sys.argv", ["check_code_health.py", "--ratchet-baseline"]), redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as raised:
                GATE.parse_arguments()
        self.assertEqual(raised.exception.code, 2)

    def test_main_below_ceiling_is_quiet_and_over_ceiling_emits_github_error(self):
        for count in (401, 1000, 1001):
            args = argparse.Namespace(check=True, base_ref=None, format="github")
            stdout, stderr = io.StringIO(), io.StringIO()
            with (patch.object(GATE, "parse_arguments", return_value=args),
                  patch.object(GATE, "load_current_baseline", return_value=baseline()),
                  patch.object(GATE, "swift_line_counts", return_value={"MyWallpaperX/Test.swift": count}),
                  redirect_stdout(stdout), redirect_stderr(stderr)):
                result = GATE.main()
            self.assertEqual(result, int(count > 1000))
            self.assertNotIn("warning", stdout.getvalue().lower() + stderr.getvalue().lower())
            if count > 1000:
                self.assertIn("::error file=MyWallpaperX/Test.swift", stdout.getvalue())
            else:
                self.assertIn("1000-line hard limit", stdout.getvalue())


if __name__ == "__main__":
    unittest.main()
