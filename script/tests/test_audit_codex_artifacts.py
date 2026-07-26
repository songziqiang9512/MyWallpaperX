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


if __name__ == "__main__":
    unittest.main()
