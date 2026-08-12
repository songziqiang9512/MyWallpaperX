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
    def test_partition_keeps_only_exact_runtime_dependencies(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-codex-audit-") as directory:
            root = Path(directory) / ".codex"
            required = root / "current-run/runtime-homes"
            stale_sibling = root / "current-run/runtime-app"
            stale_run = root / "old-run"
            required.mkdir(parents=True)
            stale_sibling.mkdir()
            stale_run.mkdir()
            kept, candidates = audit.partition_entries(root, [required])
            self.assertEqual(kept, [required])
            self.assertEqual(
                candidates,
                [stale_sibling, stale_run],
            )

    def test_required_paths_come_from_fixture_not_document_references(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-codex-audit-") as directory:
            root = Path(directory)
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
            root = Path(directory)
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


if __name__ == "__main__":
    unittest.main()
