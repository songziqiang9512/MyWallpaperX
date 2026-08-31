#!/usr/bin/env python3

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

import audit_codex_artifacts as audit


class AuditCodexArtifactsTests(unittest.TestCase):
    def test_derived_data_requires_review_instead_of_unconditional_retention(self) -> None:
        derived_data = audit.CODEX_ROOT / "DerivedData"
        self.assertNotIn(derived_data, audit.ALWAYS_KEEP)
        self.assertIn(derived_data, audit.CONDITIONAL_REVIEW)

    def test_partition_keeps_only_exact_runtime_dependencies(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-codex-audit-") as directory:
            root = Path(directory) / ".codex"
            required = root / "current-run/runtime-homes"
            unprotected_sibling = root / "current-run/runtime-app"
            unprotected_run = root / "old-run"
            required.mkdir(parents=True)
            unprotected_sibling.mkdir()
            unprotected_run.mkdir()
            kept, candidates = audit.partition_entries(root, [required])
            self.assertEqual(kept, [required])
            self.assertEqual(
                candidates,
                [unprotected_sibling, unprotected_run],
            )

    def test_required_paths_come_from_fixture_not_document_references(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-codex-audit-") as directory:
            root = Path(directory).resolve()
            fixture = root / "fixture.json"
            fixture.write_text(
                '{"schema_version":1,"sample_root":".codex/current/samples"}',
                encoding="utf-8",
            )
            with (
                mock.patch.object(audit, "REPOSITORY_ROOT", root),
                mock.patch.object(audit, "FIXTURE_CONFIG", fixture),
                mock.patch.object(
                    audit,
                    "ALWAYS_KEEP",
                    (root / ".codex/DerivedData",),
                ),
            ):
                protected, sources = audit.required_paths()
            self.assertEqual(
                protected,
                [
                    root / ".codex/DerivedData",
                    (root / ".codex/current/samples").resolve(),
                ],
            )
            self.assertEqual(sources, ["fixture.json"])

    def test_referenced_codex_paths_keep_only_existing_exact_targets(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-codex-audit-") as directory:
            root = Path(directory).resolve()
            codex = root / ".codex"
            report = codex / "formal-run/report.json"
            runtime = codex / "formal-run/runtime-app"
            report.parent.mkdir(parents=True)
            report.write_text("{}", encoding="utf-8")
            runtime.mkdir()
            document = root / "evidence.md"
            document.write_text(
                "keep `.codex/formal-run/report.json`, "
                "ignore `.codex/missing/report.json`.",
                encoding="utf-8",
            )

            referenced = audit.referenced_codex_paths(
                [document],
                root,
                codex,
            )
            self.assertEqual(referenced, [report.resolve()])
            all_references = audit.codex_reference_paths(
                [document],
                root,
                codex,
            )
            self.assertEqual(
                all_references,
                [
                    report.resolve(),
                    (codex / "missing/report.json").resolve(),
                ],
            )

            kept, candidates = audit.partition_entries(codex, referenced)
            self.assertEqual(kept, [report])
            self.assertEqual(candidates, [runtime])

    def test_inventory_marks_candidates_as_review_only(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-codex-audit-") as directory:
            root = Path(directory).resolve()
            codex = root / ".codex"
            protected = codex / "protected"
            candidate = codex / "candidate"
            protected.mkdir(parents=True)
            candidate.mkdir()
            with (
                mock.patch.object(audit, "REPOSITORY_ROOT", root),
                mock.patch.object(audit, "CODEX_ROOT", codex),
                mock.patch.object(
                    audit,
                    "CONDITIONAL_REVIEW",
                    (codex / "DerivedData",),
                ),
                mock.patch.object(audit, "required_paths", return_value=([protected], [])),
                mock.patch.object(audit, "tracked_reference_files", return_value=[]),
            ):
                report = audit.inventory()

            self.assertEqual(report["candidate_policy"]["classification"], "review-required")
            self.assertFalse(report["candidate_policy"]["deletion_authorized"])
            self.assertTrue(
                report["candidate_policy"]["tracked_prose_is_provenance_only"]
            )
            self.assertEqual(
                [item["path"] for item in report["candidates"]],
                [".codex/candidate"],
            )

    def test_tracked_prose_reference_does_not_authorize_retention(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-codex-audit-") as directory:
            root = Path(directory).resolve()
            codex = root / ".codex"
            report_path = codex / "historical-run/report.json"
            report_path.parent.mkdir(parents=True)
            report_path.write_text("{}", encoding="utf-8")
            document = root / "history.md"
            document.write_text(
                "historical provenance: `.codex/historical-run/report.json`",
                encoding="utf-8",
            )
            with (
                mock.patch.object(audit, "REPOSITORY_ROOT", root),
                mock.patch.object(audit, "CODEX_ROOT", codex),
                mock.patch.object(
                    audit,
                    "CONDITIONAL_REVIEW",
                    (codex / "DerivedData",),
                ),
                mock.patch.object(audit, "required_paths", return_value=([], [])),
                mock.patch.object(
                    audit,
                    "tracked_reference_files",
                    return_value=[document],
                ),
            ):
                inventory = audit.inventory()

            self.assertEqual(inventory["protected"], [])
            self.assertEqual(
                [item["path"] for item in inventory["candidates"]],
                [".codex/historical-run"],
            )
            self.assertEqual(
                inventory["documented_paths"],
                [".codex/historical-run/report.json"],
            )


if __name__ == "__main__":
    unittest.main()
