from __future__ import annotations

import argparse
import importlib.util
import io
import json
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


def baseline(
    *,
    review_limit: int = 400,
    hard_limit: int = 800,
    legacy_files: dict[str, int] | None = None,
    review_warning_files: dict[str, int] | None = None,
) -> dict[str, object]:
    return {
        "schemaVersion": 3,
        "reviewLineLimit": review_limit,
        "hardLineLimit": hard_limit,
        "sourceRoots": ["MyWallpaperX", "WallpaperDaemonSources"],
        "legacyFiles": legacy_files or {},
        "reviewWarningFiles": review_warning_files or {},
    }


class CodeHealthGateTests(unittest.TestCase):
    def test_authorized_thousand_line_transition_keeps_future_ratchet(self) -> None:
        self.assertEqual([], GATE.historical_problems(
            baseline(hard_limit=1000), baseline(hard_limit=800),
        ))
        self.assertTrue(GATE.historical_problems(
            baseline(hard_limit=1001), baseline(hard_limit=1000),
        ))

    def test_current_tree_warns_between_review_and_hard_limits(self) -> None:
        errors, warnings = GATE.current_tree_findings(
            baseline(legacy_files={"MyWallpaperX/Legacy.swift": 900}),
            {
                "MyWallpaperX/AtReviewLimit.swift": 400,
                "MyWallpaperX/NeedsReview.swift": 401,
                "MyWallpaperX/AtHardLimit.swift": 800,
                "MyWallpaperX/Legacy.swift": 900,
            },
        )

        self.assertEqual([], errors)
        self.assertEqual(
            {
                "MyWallpaperX/NeedsReview.swift",
                "MyWallpaperX/AtHardLimit.swift",
                "MyWallpaperX/Legacy.swift",
            },
            {path for path, _ in warnings},
        )
        self.assertTrue(all("review" in message for _, message in warnings))

    def test_current_tree_rejects_growth_and_new_file_over_hard_limit(self) -> None:
        errors, warnings = GATE.current_tree_findings(
            baseline(legacy_files={"MyWallpaperX/Legacy.swift": 900}),
            {
                "MyWallpaperX/Legacy.swift": 901,
                "MyWallpaperX/New.swift": 801,
            },
        )

        self.assertEqual([], warnings)
        self.assertEqual(2, len(errors))
        self.assertIn("grew", errors[0][1])
        self.assertIn("hard limit", errors[1][1])

    def test_current_tree_requires_ratchet_after_shrink_or_delete(self) -> None:
        errors, warnings = GATE.current_tree_findings(
            baseline(
                legacy_files={
                    "MyWallpaperX/Shrank.swift": 900,
                    "MyWallpaperX/BelowHardLimit.swift": 850,
                    "MyWallpaperX/Deleted.swift": 850,
                }
            ),
            {
                "MyWallpaperX/Shrank.swift": 875,
                "MyWallpaperX/BelowHardLimit.swift": 800,
            },
        )

        self.assertEqual([], warnings)
        self.assertEqual(3, len(errors))
        self.assertTrue(all("ratchet" in message for _, message in errors))

    def test_current_tree_locks_review_warnings_with_directional_ratchet(self) -> None:
        errors, warnings = GATE.current_tree_findings(
            baseline(
                review_warning_files={
                    "MyWallpaperX/Locked.swift": 850,
                    "MyWallpaperX/Shrank.swift": 850,
                    "MyWallpaperX/Grew.swift": 850,
                    "MyWallpaperX/Resolved.swift": 850,
                    "MyWallpaperX/Deleted.swift": 850,
                }
            ),
            {
                "MyWallpaperX/Locked.swift": 850,
                "MyWallpaperX/Shrank.swift": 849,
                "MyWallpaperX/Grew.swift": 851,
                "MyWallpaperX/Resolved.swift": 400,
            },
        )

        self.assertEqual(4, len(errors))
        messages = "\n".join(message for _, message in errors)
        self.assertIn("shrank from 850 to 849", messages)
        self.assertIn("grew from its locked review-warning allowance 850 to 851", messages)
        self.assertIn(
            "no longer exceeds the 400-line review limit; remove its review-warning entry",
            messages,
        )
        self.assertIn("review-warning entry is stale", messages)
        locked = [message for path, message in warnings if path == "MyWallpaperX/Locked.swift"]
        self.assertEqual(1, len(locked))
        self.assertIn("locked to its review-warning allowance of 850", locked[0])
        self.assertNotIn("MyWallpaperX/Resolved.swift", {path for path, _ in warnings})

    def test_history_rejects_weaker_limits_roots_and_exceptions(self) -> None:
        previous = baseline(
            legacy_files={"MyWallpaperX/Legacy.swift": 900},
            review_warning_files={"MyWallpaperX/ReviewLocked.swift": 850},
        )
        current = baseline(
            review_limit=401,
            hard_limit=801,
            legacy_files={
                "MyWallpaperX/Legacy.swift": 901,
                "MyWallpaperX/New.swift": 850,
            },
            review_warning_files={
                "MyWallpaperX/ReviewLocked.swift": 851,
                "MyWallpaperX/ReviewNew.swift": 860,
            },
        )
        current["sourceRoots"] = ["MyWallpaperX"]

        problems = GATE.historical_problems(current, previous)

        self.assertEqual(7, len(problems))
        messages = "\n".join(message for _, message in problems)
        self.assertIn("reviewLineLimit increased from 400 to 401", messages)
        self.assertIn("hardLineLimit increased from 800 to 801", messages)
        self.assertIn("source roots cannot be removed", messages)
        self.assertIn("increased from 900 to 901", messages)
        self.assertIn("new legacy exception", messages)
        self.assertIn(
            "review-warning allowance for MyWallpaperX/ReviewLocked.swift increased from 850 to 851",
            messages,
        )
        self.assertIn("new review-warning lock is not allowed: MyWallpaperX/ReviewNew.swift", messages)

    def test_history_allows_tighter_limits_and_removing_exceptions(self) -> None:
        previous = baseline(
            legacy_files={"MyWallpaperX/Legacy.swift": 900},
            review_warning_files={"MyWallpaperX/ReviewLocked.swift": 850},
        )
        current = baseline(
            review_limit=350,
            hard_limit=750,
            review_warning_files={"MyWallpaperX/ReviewLocked.swift": 800},
        )

        self.assertEqual([], GATE.historical_problems(current, previous))

    def test_schema_three_validates_limits_paths_and_lock_floors(self) -> None:
        valid = baseline()
        GATE.read_baseline_text(json.dumps(valid), "fixture")

        invalid_limits = (
            dict(valid, schemaVersion=True),
            dict(valid, schemaVersion=4),
            dict(valid, reviewLineLimit=True),
            dict(valid, hardLineLimit=400),
            dict(valid, lineLimit=400),
            dict(valid, schemaVersion=2),
        )
        for invalid in invalid_limits:
            with self.subTest(invalid=invalid):
                with self.assertRaises(ValueError):
                    GATE.read_baseline_text(json.dumps(invalid), "fixture")

        for invalid_root in ("/tmp/source", "../source", "MyWallpaperX/../Other", "MyWallpaperX/"):
            invalid = dict(valid, sourceRoots=[invalid_root])
            with self.subTest(root=invalid_root):
                with self.assertRaises(ValueError):
                    GATE.read_baseline_text(json.dumps(invalid), "fixture")

        invalid_exception = dict(
            valid,
            legacyFiles={"MyWallpaperX/AtHardLimit.swift": 800},
        )
        with self.assertRaises(ValueError):
            GATE.read_baseline_text(json.dumps(invalid_exception), "fixture")

        unmanaged = dict(
            valid,
            legacyFiles={"MyWallpaperXTests/Oversized.swift": 900},
        )
        with self.assertRaises(ValueError):
            GATE.read_baseline_text(json.dumps(unmanaged), "fixture")

        invalid_review_locks = (
            dict(valid, reviewWarningFiles="locked"),
            dict(valid, reviewWarningFiles={"MyWallpaperX/AtReviewLimit.swift": 400}),
            dict(valid, reviewWarningFiles={"MyWallpaperXTests/Oversized.swift": 500}),
            dict(
                valid,
                legacyFiles={"MyWallpaperX/Legacy.swift": 900},
                reviewWarningFiles={"MyWallpaperX/Legacy.swift": 500},
            ),
        )
        for invalid in invalid_review_locks:
            with self.subTest(invalid=invalid):
                with self.assertRaises(ValueError):
                    GATE.read_baseline_text(json.dumps(invalid), "fixture")

    def test_schema_two_is_read_only_migration_input(self) -> None:
        previous = {
            "schemaVersion": 2,
            "reviewLineLimit": 400,
            "hardLineLimit": 1000,
            "sourceRoots": ["MyWallpaperX"],
            "legacyFiles": {"MyWallpaperX/Legacy.swift": 1001},
        }

        parsed = GATE.read_baseline_text(json.dumps(previous), "fixture")

        self.assertEqual(2, parsed["schemaVersion"])
        self.assertEqual({}, parsed["reviewWarningFiles"])

    def test_schema_one_is_read_only_migration_input(self) -> None:
        previous = {
            "schemaVersion": 1,
            "lineLimit": 400,
            "sourceRoots": ["MyWallpaperX"],
            "legacyFiles": {"MyWallpaperX/Legacy.swift": 900},
        }

        parsed = GATE.read_baseline_text(json.dumps(previous), "fixture")

        self.assertEqual(1, parsed["schemaVersion"])
        self.assertEqual(400, parsed["reviewLineLimit"])
        self.assertIsNone(parsed["hardLineLimit"])
        self.assertEqual({}, parsed["reviewWarningFiles"])
        self.assertNotIn("lineLimit", parsed)

    def test_source_root_membership_uses_path_components(self) -> None:
        roots = ["MyWallpaperX", "WallpaperDaemonSources"]

        self.assertTrue(GATE.belongs_to_source_root("MyWallpaperX/App/AppDelegate.swift", roots))
        self.assertTrue(GATE.belongs_to_source_root("WallpaperDaemonSources/main.swift", roots))
        self.assertFalse(GATE.belongs_to_source_root("MyWallpaperXTests/AppTests.swift", roots))
        self.assertFalse(GATE.belongs_to_source_root("MyWallpaperXBackup/File.swift", roots))

    def test_ratchet_removes_resolved_entries_and_lowers_remaining_allowance(self) -> None:
        current = baseline(
            legacy_files={
                "MyWallpaperX/Shrank.swift": 900,
                "MyWallpaperX/BelowHardLimit.swift": 850,
                "MyWallpaperX/Deleted.swift": 850,
            },
            review_warning_files={
                "MyWallpaperX/ReviewResolved.swift": 850,
                "MyWallpaperX/ReviewShrank.swift": 850,
                "MyWallpaperX/ReviewDeleted.swift": 850,
            },
        )
        counts = {
            "MyWallpaperX/Shrank.swift": 875,
            "MyWallpaperX/BelowHardLimit.swift": 800,
            "MyWallpaperX/ReviewResolved.swift": 400,
            "MyWallpaperX/ReviewShrank.swift": 820,
        }

        with tempfile.TemporaryDirectory() as directory:
            output_path = Path(directory) / "baseline.json"
            with (
                patch.object(GATE, "BASELINE_PATH", output_path),
                redirect_stdout(io.StringIO()),
            ):
                result = GATE.ratchet_baseline(current, counts)
            updated = json.loads(output_path.read_text(encoding="utf-8"))

        self.assertEqual(0, result)
        self.assertEqual({"MyWallpaperX/Shrank.swift": 875}, updated["legacyFiles"])
        self.assertEqual(
            {"MyWallpaperX/ReviewShrank.swift": 820}, updated["reviewWarningFiles"]
        )

    def test_ratchet_cannot_add_or_expand_hard_limit_exception(self) -> None:
        current = baseline(legacy_files={"MyWallpaperX/Legacy.swift": 900})
        counts = {
            "MyWallpaperX/Legacy.swift": 901,
            "MyWallpaperX/New.swift": 801,
        }

        with redirect_stderr(io.StringIO()):
            result = GATE.ratchet_baseline(current, counts)

        self.assertEqual(1, result)

    def test_ratchet_cannot_expand_review_warning_allowance(self) -> None:
        current = baseline(review_warning_files={"MyWallpaperX/Locked.swift": 850})

        with redirect_stderr(io.StringIO()) as stderr:
            grew = GATE.ratchet_baseline(current, {"MyWallpaperX/Locked.swift": 851})
            breached_hard_limit = GATE.ratchet_baseline(
                current, {"MyWallpaperX/Locked.swift": 1001}
            )

        self.assertEqual(1, grew)
        self.assertEqual(1, breached_hard_limit)
        self.assertIn(
            "cannot ratchet a review-warning file that grew from 850 to 851",
            stderr.getvalue(),
        )
        self.assertIn(
            "cannot ratchet a review-warning file that grew from 850 to 1001",
            stderr.getvalue(),
        )
        self.assertNotIn("cannot add a legacy exception", stderr.getvalue())

    def test_main_warning_only_succeeds_and_labels_warning(self) -> None:
        arguments = argparse.Namespace(
            check=True,
            ratchet_baseline=False,
            base_ref=None,
            format="text",
        )
        current = baseline()
        stdout = io.StringIO()
        stderr = io.StringIO()

        with (
            patch.object(GATE, "parse_arguments", return_value=arguments),
            patch.object(GATE, "load_current_baseline", return_value=current),
            patch.object(
                GATE,
                "swift_line_counts",
                return_value={"MyWallpaperX/NeedsReview.swift": 401},
            ),
            redirect_stdout(stdout),
            redirect_stderr(stderr),
        ):
            result = GATE.main()

        self.assertEqual(0, result)
        self.assertIn("WARNING MyWallpaperX/NeedsReview.swift", stderr.getvalue())
        self.assertNotIn("ERROR", stderr.getvalue())
        self.assertIn("1 warnings", stdout.getvalue())

    def test_main_hard_limit_error_fails_and_labels_error(self) -> None:
        arguments = argparse.Namespace(
            check=True,
            ratchet_baseline=False,
            base_ref=None,
            format="github",
        )
        current = baseline()
        stdout = io.StringIO()

        with (
            patch.object(GATE, "parse_arguments", return_value=arguments),
            patch.object(GATE, "load_current_baseline", return_value=current),
            patch.object(
                GATE,
                "swift_line_counts",
                return_value={"MyWallpaperX/TooLarge.swift": 801},
            ),
            redirect_stdout(stdout),
        ):
            result = GATE.main()

        self.assertEqual(1, result)
        self.assertIn("::error file=MyWallpaperX/TooLarge.swift", stdout.getvalue())
        self.assertNotIn("::warning", stdout.getvalue())


if __name__ == "__main__":
    unittest.main()
