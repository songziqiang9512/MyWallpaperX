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


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "check_scene_defense.py"
SPEC = importlib.util.spec_from_file_location("check_scene_defense", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
GATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GATE)


def baseline(
    *,
    dead: list[dict[str, str]] | None = None,
    inventory: list[dict[str, str]] | None = None,
    helpers: list[dict[str, object]] | None = None,
    swallows: list[dict[str, object]] | None = None,
    source_root: str = "Scene",
) -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "sourceRoot": source_root,
        "notes": ["locked inventory"],
        "canonicalHelpers": helpers
        if helpers is not None
        else [
            {
                "name": "matches",
                "allowedCopies": 1,
                "canonical": None,
                "owner": "fixture owner",
                "retirement": "fixture retirement",
            }
        ],
        "swallowPatterns": swallows
        if swallows is not None
        else [
            {
                "id": "regex",
                "pattern": r"try\?[ \t]+NSRegularExpression\(",
                "allowedOccurrences": 0,
                "owner": "fixture owner",
                "retirement": "fixture retirement",
            }
        ],
        "deadEntries": dead or [],
        "inventoryEntries": inventory or [],
    }


def measurements(
    *,
    dead: list[dict[str, str]] | None = None,
    inventory: list[dict[str, str]] | None = None,
    helpers: dict[str, int] | None = None,
    swallows: dict[str, int] | None = None,
) -> dict[str, object]:
    return {
        "deadEntries": dead or [],
        "inventoryEntries": inventory or [],
        "canonicalHelpers": helpers if helpers is not None else {"matches": 1},
        "swallowPatterns": swallows if swallows is not None else {"regex": 0},
    }


def meta_helper(
    name: str, copies: int, canonical: str | None = None, owner: str = "fixture owner"
) -> dict[str, object]:
    return {
        "name": name,
        "allowedCopies": copies,
        "canonical": canonical,
        "owner": owner,
        "retirement": "fixture retirement",
    }


def meta_pattern(
    pattern_id: str, occurrences: int, pattern: str = r"try\?[ \t]+NSRegularExpression\("
) -> dict[str, object]:
    return {
        "id": pattern_id,
        "pattern": pattern,
        "allowedOccurrences": occurrences,
        "owner": "fixture owner",
        "retirement": "fixture retirement",
    }


def ratchet_args(**overrides: object) -> argparse.Namespace:
    values: dict[str, object] = {
        "accept_growth": False,
        "reason": "",
        "base_ref": None,
        "drop_unused_acknowledgements": False,
    }
    values.update(overrides)
    return argparse.Namespace(**values)


def write(root: Path, relative: str, text: str) -> None:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class SceneDefenseGateTests(unittest.TestCase):
    def test_dead_entry_requires_zero_references_repo_wide(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(
                root,
                "Scene/Holder.swift",
                "enum Holder {\n    static func orphan() {}\n    static func used() {}\n}\n",
            )
            write(root, "Scene/Caller.swift", "func call() { Holder.used() }\n")

            with patch.object(GATE, "REPO_ROOT", root):
                sources = GATE.scene_sources(["Scene/Holder.swift", "Scene/Caller.swift"], "Scene")
                dead, inventory = GATE.count_dead_entries(
                    sources, ["Scene/Holder.swift", "Scene/Caller.swift"]
                )

        self.assertEqual([], inventory)
        detected = {entry["name"] for entry in dead}
        self.assertIn("orphan", detected)
        self.assertNotIn("used", detected)
        self.assertNotIn("Holder", detected)

    def test_inventory_annotation_records_a_named_waiver(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(
                root,
                "Scene/Kept.swift",
                "// inventory-entry: reserved for the next vertical slice\nenum Kept {}\n",
            )

            with patch.object(GATE, "REPO_ROOT", root):
                sources = GATE.scene_sources(["Scene/Kept.swift"], "Scene")
                dead, inventory = GATE.count_dead_entries(sources, ["Scene/Kept.swift"])

        self.assertEqual([], dead)
        self.assertEqual(["Kept"], [entry["name"] for entry in inventory])
        self.assertTrue(inventory[0]["reason"])

    def test_annotation_trailing_comment_does_not_leak_to_the_next_declaration(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(
                root,
                "Scene/Pair.swift",
                "enum Waived {}  // inventory-entry: covers Waived only\nenum Leaked {}\n",
            )

            with patch.object(GATE, "REPO_ROOT", root):
                sources = GATE.scene_sources(["Scene/Pair.swift"], "Scene")
                dead, inventory = GATE.count_dead_entries(sources, ["Scene/Pair.swift"])

        self.assertEqual(["Waived"], [entry["name"] for entry in inventory])
        self.assertIn("Leaked", {entry["name"] for entry in dead})

    def test_private_declarations_stay_out_of_the_inventory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(root, "Scene/Private.swift", "private enum Holder {\n    private static func hidden() {}\n}\n")

            with patch.object(GATE, "REPO_ROOT", root):
                sources = GATE.scene_sources(["Scene/Private.swift"], "Scene")
                dead, _ = GATE.count_dead_entries(sources, ["Scene/Private.swift"])

        self.assertEqual([], dead)

    def test_canonical_helper_counting_counts_definitions_only(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(root, "Scene/One.swift", "func matches(_ value: Int) {}\nlet alias = matches(1)\n")
            write(root, "Scene/Two.swift", "func matches(_ value: Int) {}\n")

            with patch.object(GATE, "REPO_ROOT", root):
                sources = GATE.scene_sources(["Scene/One.swift", "Scene/Two.swift"], "Scene")
                counts = GATE.count_canonical_helpers(
                    [{"name": "matches", "allowedCopies": 2, "canonical": None}], sources
                )

        self.assertEqual({"matches": 2}, counts)

    def test_swallow_pattern_counting_uses_the_reviewed_pattern(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(
                root,
                "Scene/Digest.swift",
                "func digest(_ payload: Payload) -> Data {\n"
                "    (try? JSONEncoder().encode(payload)) ?? Data()\n"
                "}\n",
            )
            write(root, "Scene/Quiet.swift", "let pattern = try! NSRegularExpression(pattern: \"x\")\n")

            with patch.object(GATE, "REPO_ROOT", root):
                sources = GATE.scene_sources(["Scene/Digest.swift", "Scene/Quiet.swift"], "Scene")
                counts = GATE.count_swallow_patterns(
                    [
                        meta_pattern("optional-constant-swallow", 1, r"\(try\?[^\n]*\)[ \t]*\?\?")
                    ],
                    sources,
                )

        self.assertEqual({"optional-constant-swallow": 1}, counts)

    def test_check_reports_new_dead_entries_and_stale_locks(self) -> None:
        errors, _ = GATE.evaluate(
            baseline(dead=[{"name": "gone", "file": "Scene/Gone.swift"}]),
            measurements(dead=[{"name": "orphan", "file": "Scene/Holder.swift", "kind": "func"}]),
        )

        self.assertTrue(any("orphan" in message and "no reference" in message for message in errors))
        self.assertTrue(any("gone" in message and "locked dead entry" in message for message in errors))

    def test_check_requires_a_ratchet_after_helper_shrink(self) -> None:
        errors, _ = GATE.evaluate(
            baseline(helpers=[meta_helper("matches", 3)]),
            measurements(helpers={"matches": 2}),
        )

        self.assertTrue(any("shrank from 3 to 2" in message for message in errors))

    def test_check_rejects_helper_and_swallow_growth(self) -> None:
        errors, _ = GATE.evaluate(
            baseline(
                helpers=[meta_helper("matches", 1, canonical="Scene/Canonical.swift")],
                swallows=[meta_pattern("regex", 1)],
            ),
            measurements(helpers={"matches": 3}, swallows={"regex": 2}),
        )

        self.assertTrue(any("reuse" in message for message in errors))
        self.assertTrue(any("swallow pattern regex matched 2 times" in message for message in errors))

    def test_check_requires_a_lock_for_a_new_inventory_waiver(self) -> None:
        errors, _ = GATE.evaluate(
            baseline(),
            measurements(inventory=[{"name": "Kept", "file": "Scene/Kept.swift", "kind": "enum", "reason": "later"}]),
        )

        self.assertTrue(any("inventory waiver Kept is not in the baseline" in message for message in errors))

    def test_growth_guard_blocks_allowance_and_inventory_expansion_against_a_ref(self) -> None:
        ref = baseline(helpers=[meta_helper("matches", 1)])
        expanded = baseline(
            helpers=[meta_helper("matches", 4)],
            inventory=[{"name": "Kept", "file": "Scene/Kept.swift", "kind": "enum", "reason": "later"}],
        )

        growth, set_changes = GATE.check_growth(ref, expanded)

        self.assertTrue(any("allowance grew from 1 to 4" in message for message in growth))
        self.assertTrue(any("inventory waiver grew with Kept" in message for message in growth))
        self.assertEqual([], set_changes)

    def test_growth_guard_reports_reviewed_set_changes(self) -> None:
        collapsed = baseline(helpers=[meta_helper("matches", 1)])
        swapped = baseline(helpers=[meta_helper("sha256", 1)])

        growth, set_changes = GATE.check_growth(collapsed, swapped)

        self.assertEqual([], growth)
        self.assertTrue(any("sha256 was added" in message for message in set_changes))
        self.assertTrue(any("matches was removed" in message for message in set_changes))

    def test_ratchet_requires_accept_growth_for_new_dead_entries(self) -> None:
        current = measurements(dead=[{"name": "orphan", "file": "Scene/Holder.swift", "kind": "func"}])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(root, "script/scene_defense_baseline.json", json.dumps(baseline()))

            with patch.object(GATE, "REPO_ROOT", root):
                with redirect_stderr(io.StringIO()):
                    refused = GATE.ratchet(baseline(), current, ratchet_args())
                unlocked = json.loads(
                    (root / "script/scene_defense_baseline.json").read_text(encoding="utf-8")
                )
                with redirect_stderr(io.StringIO()):
                    missing_reason = GATE.ratchet(
                        baseline(), current, ratchet_args(accept_growth=True)
                    )
                with redirect_stdout(io.StringIO()):
                    accepted = GATE.ratchet(
                        baseline(),
                        current,
                        ratchet_args(accept_growth=True, reason="first lock of the measured inventory"),
                    )
                locked = json.loads(
                    (root / "script/scene_defense_baseline.json").read_text(encoding="utf-8")
                )

        self.assertEqual(2, refused)
        self.assertEqual([], unlocked["deadEntries"])
        self.assertEqual(2, missing_reason)
        self.assertEqual(0, accepted)
        self.assertEqual(
            [{"name": "orphan", "file": "Scene/Holder.swift", "kind": "func"}], locked["deadEntries"]
        )
        self.assertEqual(
            [
                {
                    "detail": "dead inventory grew with orphan in Scene/Holder.swift",
                    "reason": "first lock of the measured inventory",
                }
            ],
            locked["acknowledgedChanges"],
        )

    def test_ratchet_requires_accept_growth_for_helper_widening(self) -> None:
        current = measurements(helpers={"matches": 5})
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(root, "script/scene_defense_baseline.json", json.dumps(baseline()))

            with patch.object(GATE, "REPO_ROOT", root):
                with redirect_stderr(io.StringIO()):
                    refused = GATE.ratchet(baseline(), current, ratchet_args())
                with redirect_stdout(io.StringIO()):
                    accepted = GATE.ratchet(
                        baseline(),
                        current,
                        ratchet_args(accept_growth=True, reason="batch 7 adds the reviewed helper"),
                    )
                locked = json.loads(
                    (root / "script/scene_defense_baseline.json").read_text(encoding="utf-8")
                )

        self.assertEqual(2, refused)
        self.assertEqual(0, accepted)
        self.assertEqual(5, locked["canonicalHelpers"][0]["allowedCopies"])

    def test_set_changes_need_a_matching_acknowledgement(self) -> None:
        arguments = argparse.Namespace(
            check=True, audit=False, ratchet_baseline=False, base_ref="BASE", format="text", drop_unused_acknowledgements=False)
        ref = baseline(helpers=[meta_helper("matches", 1)])
        current = baseline(helpers=[meta_helper("sha256", 1)])
        measured = measurements(helpers={"sha256": 1})
        details = [
            "canonical helper sha256 was added to the reviewed set",
            "canonical helper matches was removed from the reviewed set",
        ]

        def run(gate_baseline: dict[str, object]) -> tuple[int, str]:
            stdout = io.StringIO()
            with (
                patch.object(GATE, "parse_arguments", return_value=arguments),
                patch.object(GATE, "load_current_baseline", return_value=gate_baseline),
                patch.object(GATE, "scene_source_root", return_value="Scene"),
                patch.object(GATE, "tracked_paths", return_value=[]),
                patch.object(GATE, "measure", return_value=measured),
                patch.object(GATE, "baseline_at_ref", return_value=ref),
                redirect_stdout(stdout),
                redirect_stderr(io.StringIO()),
            ):
                return GATE.main(), stdout.getvalue()

        unacknowledged, unacknowledged_output = run(current)
        partial, partial_output = run(
            {
                **current,
                "acknowledgedChanges": [{"detail": details[0], "reason": "reviewed"}],
            }
        )
        acknowledged, acknowledged_output = run(
            {
                **current,
                "acknowledgedChanges": [
                    {"detail": details[0], "reason": "reviewed"},
                    {"detail": details[1], "reason": "reviewed"},
                ],
            }
        )

        self.assertEqual(1, unacknowledged)
        self.assertIn("land the reviewed-set change deliberately", unacknowledged_output)
        self.assertEqual(1, partial)
        self.assertIn("was removed from the reviewed set", partial_output)
        self.assertEqual(0, acknowledged)
        self.assertIn("acknowledged reviewed-set change", acknowledged_output)

    def test_ratchet_preserves_recorded_acknowledgements(self) -> None:
        recorded = {
            **baseline(),
            "acknowledgedChanges": [
                {"detail": "dead inventory grew with orphan in Scene/Holder.swift", "reason": "reviewed"}
            ],
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(root, "script/scene_defense_baseline.json", json.dumps(recorded))

            with patch.object(GATE, "REPO_ROOT", root), redirect_stdout(io.StringIO()):
                GATE.ratchet(recorded, measurements(), ratchet_args())
                locked = json.loads(
                    (root / "script/scene_defense_baseline.json").read_text(encoding="utf-8")
                )

        self.assertEqual(
            [{"detail": "dead inventory grew with orphan in Scene/Holder.swift", "reason": "reviewed"}],
            locked["acknowledgedChanges"],
        )

    def test_ratchet_requires_a_reason_to_retire_a_family(self) -> None:
        current = measurements(helpers={"matches": 0}, swallows={"regex": 0})
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(root, "script/scene_defense_baseline.json", json.dumps(baseline()))

            with patch.object(GATE, "REPO_ROOT", root):
                with redirect_stderr(io.StringIO()):
                    refused = GATE.ratchet(baseline(), current, ratchet_args())
                with redirect_stdout(io.StringIO()):
                    accepted = GATE.ratchet(
                        baseline(),
                        current,
                        ratchet_args(reason="family merged into the reviewed home"),
                    )
                locked = json.loads(
                    (root / "script/scene_defense_baseline.json").read_text(encoding="utf-8")
                )

        self.assertEqual(2, refused)
        self.assertEqual(0, accepted)
        details = {entry["detail"] for entry in locked["acknowledgedChanges"]}
        self.assertIn("retired canonical helper matches: allowance 1 -> 0", details)

    def test_reviewed_target_and_pattern_changes_are_detected(self) -> None:
        ref = baseline(
            helpers=[meta_helper("matches", 1, canonical="Scene/OLD.swift")],
            swallows=[meta_pattern("regex", 1)],
        )
        current = baseline(
            helpers=[meta_helper("matches", 1, canonical="Scene/NEW.swift")],
            swallows=[meta_pattern("regex", 1, r"ZZZ-never-matches")],
        )

        growth, changes = GATE.check_growth(ref, current)

        self.assertEqual([], growth)
        self.assertTrue(any("target changed from 'Scene/OLD.swift' to 'Scene/NEW.swift'" in m for m in changes))
        self.assertTrue(any("pattern text changed" in m for m in changes))

    def test_locked_dead_entries_hold_instead_of_looping(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(root, "Scene/Lone.swift", "enum Lone {\n    static func orphanLeaf() {}\n}\n")
            write(root, "script/scene_defense_baseline.json", json.dumps(baseline()))

            with patch.object(GATE, "REPO_ROOT", root):
                paths = ["Scene/Lone.swift", "script/scene_defense_baseline.json"]
                first = GATE.measure(paths, baseline())
                locked = GATE.ratcheted_baseline(baseline(), first)
                write(root, "script/scene_defense_baseline.json", json.dumps(locked))
                second = GATE.measure(paths, locked)
                errors, warnings = GATE.evaluate(locked, second)

        self.assertEqual({"Lone", "orphanLeaf"}, {entry["name"] for entry in first["deadEntries"]})
        self.assertEqual([], errors)
        self.assertEqual(2, len(warnings))

    def test_check_json_format_reports_structured_result(self) -> None:
        arguments = argparse.Namespace(
            check=True, audit=False, ratchet_baseline=False, base_ref=None, format="json", drop_unused_acknowledgements=False)
        measured = measurements(dead=[{"name": "orphan", "file": "Scene/Holder.swift", "kind": "func"}])
        stdout = io.StringIO()
        with (
            patch.object(GATE, "parse_arguments", return_value=arguments),
            patch.object(GATE, "load_current_baseline", return_value=baseline()),
            patch.object(GATE, "scene_source_root", return_value="Scene"),
            patch.object(GATE, "tracked_paths", return_value=["Scene/Holder.swift"]),
            patch.object(GATE, "measure", return_value=measured),
            redirect_stdout(stdout),
            redirect_stderr(io.StringIO()),
        ):
            result = GATE.main()

        payload = json.loads(stdout.getvalue())
        self.assertEqual(1, result)
        self.assertEqual("failed", payload["result"])
        self.assertTrue(any("orphan" in message for message in payload["errors"]))

    def test_baseline_loader_requires_owner_and_retirement(self) -> None:
        payload = baseline(
            helpers=[{"name": "matches", "allowedCopies": 1, "canonical": None, "retirement": "later"}]
        )

        with self.assertRaises(ValueError):
            GATE.load_baseline(json.dumps(payload), "fixture")

    def test_ratchet_preserves_notes_and_entry_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(root, "script/scene_defense_baseline.json", json.dumps(baseline()))

            with patch.object(GATE, "REPO_ROOT", root), redirect_stdout(io.StringIO()):
                GATE.ratchet(baseline(), measurements(), ratchet_args())
                locked = json.loads(
                    (root / "script/scene_defense_baseline.json").read_text(encoding="utf-8")
                )

        self.assertEqual(["locked inventory"], locked["notes"])
        self.assertIsNone(locked["canonicalHelpers"][0]["canonical"])

    def test_ratchet_rejects_a_base_ref_combination(self) -> None:
        with redirect_stderr(io.StringIO()):
            result = GATE.ratchet(baseline(), measurements(), ratchet_args(base_ref="HEAD"))

        self.assertEqual(2, result)

    def test_invalid_base_ref_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            GATE.baseline_at_ref("definitely-not-a-real-ref")

    def test_main_rejects_a_source_root_mismatch(self) -> None:
        arguments = argparse.Namespace(
            check=True, audit=False, ratchet_baseline=False, base_ref=None, format="text", drop_unused_acknowledgements=False)
        stdout = io.StringIO()
        with (
            patch.object(GATE, "parse_arguments", return_value=arguments),
            patch.object(GATE, "load_current_baseline", return_value=baseline(source_root="Elsewhere")),
            patch.object(GATE, "scene_source_root", return_value="Scene"),
            redirect_stdout(stdout),
            redirect_stderr(stdout),
        ):
            result = GATE.main()

        self.assertEqual(2, result)
        self.assertIn("does not match", stdout.getvalue())

    def test_main_fails_on_an_unlocked_dead_entry(self) -> None:
        arguments = argparse.Namespace(
            check=True, audit=False, ratchet_baseline=False, base_ref=None, format="text", drop_unused_acknowledgements=False)
        measured = measurements(dead=[{"name": "orphan", "file": "Scene/Holder.swift", "kind": "func"}])
        stdout = io.StringIO()
        with (
            patch.object(GATE, "parse_arguments", return_value=arguments),
            patch.object(GATE, "load_current_baseline", return_value=baseline()),
            patch.object(GATE, "scene_source_root", return_value="Scene"),
            patch.object(GATE, "tracked_paths", return_value=["Scene/Holder.swift"]),
            patch.object(GATE, "measure", return_value=measured),
            redirect_stdout(stdout),
            redirect_stderr(io.StringIO()),
        ):
            result = GATE.main()

        self.assertEqual(1, result)
        self.assertIn("error:", stdout.getvalue())
        self.assertIn("scene defense ratchet failed", stdout.getvalue())

    def test_github_format_emits_annotations(self) -> None:
        arguments = argparse.Namespace(
            check=True, audit=False, ratchet_baseline=False, base_ref=None, format="github", drop_unused_acknowledgements=False)
        measured = measurements(dead=[{"name": "orphan", "file": "Scene/Holder.swift", "kind": "func"}])
        stdout = io.StringIO()
        with (
            patch.object(GATE, "parse_arguments", return_value=arguments),
            patch.object(GATE, "load_current_baseline", return_value=baseline()),
            patch.object(GATE, "scene_source_root", return_value="Scene"),
            patch.object(GATE, "tracked_paths", return_value=["Scene/Holder.swift"]),
            patch.object(GATE, "measure", return_value=measured),
            redirect_stdout(stdout),
            redirect_stderr(io.StringIO()),
        ):
            result = GATE.main()

        self.assertEqual(1, result)
        self.assertIn("::error title=scene-defense::", stdout.getvalue())

    def test_unused_acknowledgements_are_reported(self) -> None:
        arguments = argparse.Namespace(
            check=True, audit=False, ratchet_baseline=False, base_ref="BASE", format="text", drop_unused_acknowledgements=False)
        ref = baseline(helpers=[meta_helper("matches", 1)])
        current = {
            **ref,
            "acknowledgedChanges": [
                {"detail": "canonical helper ghost was added to the reviewed set", "reason": "stale"}
            ],
        }
        stdout = io.StringIO()
        with (
            patch.object(GATE, "parse_arguments", return_value=arguments),
            patch.object(GATE, "load_current_baseline", return_value=current),
            patch.object(GATE, "scene_source_root", return_value="Scene"),
            patch.object(GATE, "tracked_paths", return_value=[]),
            patch.object(GATE, "measure", return_value=measurements()),
            patch.object(GATE, "baseline_at_ref", return_value=ref),
            redirect_stdout(stdout),
            redirect_stderr(io.StringIO()),
        ):
            result = GATE.main()

        self.assertEqual(0, result)
        self.assertIn("not used by this base ref", stdout.getvalue())
        self.assertIn("canonical helper ghost", stdout.getvalue())

    def test_ratchet_prunes_only_when_asked_and_only_against_the_given_ref(self) -> None:
        current = measurements(helpers={"matches": 1})
        stale = {"detail": "canonical helper ghost was added to the reviewed set", "reason": "stale"}
        older_ref = baseline(helpers=[meta_helper("matches", 0)])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            working = baseline(helpers=[meta_helper("matches", 1)])
            working["acknowledgedChanges"] = [stale]
            write(root, "script/scene_defense_baseline.json", json.dumps(working))

            with patch.object(GATE, "REPO_ROOT", root), redirect_stdout(io.StringIO()):
                default_result = GATE.ratchet(working, current, ratchet_args())
                default_locked = json.loads(
                    (root / "script/scene_defense_baseline.json").read_text(encoding="utf-8")
                )
            self.assertEqual(0, default_result)
            self.assertEqual(
                [stale],
                default_locked["acknowledgedChanges"],
                "without the flag every acknowledgement is kept: older refs may still need it",
            )

            prune_output = io.StringIO()
            with (
                patch.object(GATE, "REPO_ROOT", root),
                patch.object(GATE, "baseline_at_ref", return_value=older_ref),
                redirect_stdout(prune_output),
            ):
                prune_result = GATE.ratchet(
                    working,
                    current,
                    ratchet_args(base_ref="HEAD~1", drop_unused_acknowledgements=True),
                )
                pruned_locked = json.loads(
                    (root / "script/scene_defense_baseline.json").read_text(encoding="utf-8")
                )

        self.assertEqual(0, prune_result)
        self.assertIn("dropped 1 acknowledgedChanges", prune_output.getvalue())
        self.assertNotIn("acknowledgedChanges", pruned_locked)

    def test_pruning_keeps_what_the_run_recorded_and_what_the_ref_needs(self) -> None:
        current = measurements(helpers={"matches": 2})
        recorded = {
            "detail": "canonical helper matches allowance grew from 1 to 2",
            "reason": "accepted in this run",
        }
        still_needed = {
            "detail": "canonical helper matches was added to the reviewed set",
            "reason": "older refs still need it",
        }
        stale = {"detail": "canonical helper ghost was added to the reviewed set", "reason": "stale"}
        reference = baseline(helpers=[meta_helper("matches", 1)])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            working = baseline(helpers=[meta_helper("matches", 1)])
            working["acknowledgedChanges"] = [recorded, still_needed, stale]
            write(root, "script/scene_defense_baseline.json", json.dumps(working))

            with (
                patch.object(GATE, "REPO_ROOT", root),
                patch.object(GATE, "baseline_at_ref", return_value=reference),
                redirect_stdout(io.StringIO()),
            ):
                result = GATE.ratchet(
                    working,
                    current,
                    ratchet_args(
                        accept_growth=True,
                        reason="accepted in this run",
                        base_ref="HEAD~1",
                        drop_unused_acknowledgements=True,
                    ),
                )
                locked = json.loads(
                    (root / "script/scene_defense_baseline.json").read_text(encoding="utf-8")
                )

        self.assertEqual(0, result)
        details = {entry["detail"] for entry in locked["acknowledgedChanges"]}
        self.assertIn(recorded["detail"], details, "the run's own record must survive pruning")
        self.assertNotIn(stale["detail"], details, "entries the ref never needed are pruned")

    def test_pruning_keeps_acknowledgements_when_the_ref_has_no_baseline(self) -> None:
        recorded = {"detail": "canonical helper matches was added to the reviewed set", "reason": "keep"}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            working = baseline()
            working["acknowledgedChanges"] = [recorded]
            write(root, "script/scene_defense_baseline.json", json.dumps(working))

            with (
                patch.object(GATE, "REPO_ROOT", root),
                patch.object(GATE, "baseline_at_ref", return_value=None),
                redirect_stdout(io.StringIO()),
                redirect_stderr(io.StringIO()),
            ):
                result = GATE.ratchet(
                    working,
                    measurements(),
                    ratchet_args(base_ref="OLD", drop_unused_acknowledgements=True),
                )
                locked = json.loads(
                    (root / "script/scene_defense_baseline.json").read_text(encoding="utf-8")
                )

        self.assertEqual(0, result)
        self.assertEqual([recorded], locked["acknowledgedChanges"])

    def test_pruning_rejects_an_unknown_ref(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(root, "script/scene_defense_baseline.json", json.dumps(baseline()))
            with patch.object(GATE, "REPO_ROOT", root), redirect_stderr(io.StringIO()):
                result = GATE.ratchet(
                    baseline(),
                    measurements(),
                    ratchet_args(base_ref="nope", drop_unused_acknowledgements=True),
                )

        self.assertEqual(2, result)

    def test_drop_flag_only_applies_to_ratchet(self) -> None:
        arguments = argparse.Namespace(
            check=True,
            audit=False,
            ratchet_baseline=False,
            base_ref=None,
            format="text",
            drop_unused_acknowledgements=True,
        )
        with (
            patch.object(GATE, "parse_arguments", return_value=arguments),
            patch.object(GATE, "load_current_baseline", return_value=baseline()),
            patch.object(GATE, "scene_source_root", return_value="Scene"),
            patch.object(GATE, "tracked_paths", return_value=[]),
            patch.object(GATE, "measure", return_value=measurements()),
            redirect_stdout(io.StringIO()),
            redirect_stderr(io.StringIO()),
        ):
            result = GATE.main()

        self.assertEqual(2, result)

    def test_drop_unused_acknowledgements_requires_a_base_ref(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(root, "script/scene_defense_baseline.json", json.dumps(baseline()))
            with patch.object(GATE, "REPO_ROOT", root), redirect_stderr(io.StringIO()):
                result = GATE.ratchet(
                    baseline(), measurements(), ratchet_args(drop_unused_acknowledgements=True)
                )

        self.assertEqual(2, result)

    def test_ratchet_keeps_acknowledgements_by_default_even_with_a_reference(self) -> None:
        current = measurements(helpers={"matches": 1})
        recorded = {
            "detail": "canonical helper matches allowance grew from 0 to 1",
            "reason": "recorded before the first commit",
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            working = baseline(helpers=[meta_helper("matches", 1)])
            working["acknowledgedChanges"] = [recorded]
            write(root, "script/scene_defense_baseline.json", json.dumps(working))

            with (
                patch.object(GATE, "REPO_ROOT", root),
                patch.object(GATE, "baseline_at_ref", return_value=baseline(helpers=[meta_helper("matches", 0)])),
                redirect_stdout(io.StringIO()),
            ):
                result = GATE.ratchet(working, current, ratchet_args())
                locked = json.loads(
                    (root / "script/scene_defense_baseline.json").read_text(encoding="utf-8")
                )

        self.assertEqual(0, result)
        self.assertEqual([recorded], locked["acknowledgedChanges"])

    def test_baseline_loader_rejects_unsupported_schema(self) -> None:
        payload = dict(baseline())
        payload["schemaVersion"] = 2

        with self.assertRaises(ValueError):
            GATE.load_baseline(json.dumps(payload), "fixture")

    def test_baseline_loader_rejects_empty_entry_metadata(self) -> None:
        payload = baseline(helpers=[meta_helper("matches", 1, owner="  ")])

        with self.assertRaises(ValueError):
            GATE.load_baseline(json.dumps(payload), "fixture")


if __name__ == "__main__":
    unittest.main()
