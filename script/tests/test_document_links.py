from __future__ import annotations

from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from script.document_links import markdown_anchors, relative_link_violations


class DocumentLinkTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="mwx-document-links-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        subprocess.run(["git", "init", "--quiet"], cwd=self.root, check=True, capture_output=True)
        (self.root / "docs").mkdir()

    def check(self, text: str) -> list[str]:
        (self.root / "docs/entry.md").write_text(text)
        return relative_link_violations(self.root, ["docs/entry.md"])

    def test_permanent_id_is_stable_for_punctuation_sensitive_heading(self) -> None:
        (self.root / "docs/target.md").write_text(
            '## 2026-09-14 `3775355045 / 3775373546` 双视频 command generation 闭环\n'
            '<a id="video-command-generation"></a>\n')
        self.assertEqual(self.check("[result](target.md#video-command-generation)"), [])
        self.assertIn("missing fragment", self.check("[wrong](target.md#video-command-generation-missing)")[0])

    def test_repeated_headings_and_explicit_ids_exclude_fenced_examples(self) -> None:
        self.assertEqual(markdown_anchors(
            '# Same\n## Same\n## Same-1\n<a class="x" id="explicit"></a>\n'
            '```html\n<a id="fake"></a>\n## Hidden\n```\n'),
            {"same", "same-1", "same-1-1", "explicit"})

    def test_encoded_paths_and_real_fragments_remain_required(self) -> None:
        (self.root / "docs/with space.md").write_text("# Two  words\n## 中文\n")
        self.assertEqual(self.check("[valid](with%20space.md#two-words) [中文](with%20space.md#%E4%B8%AD%E6%96%87)"), [])
        self.assertEqual(self.check("[missing](gone.md)"), ["docs/entry.md -> gone.md"])
        self.assertEqual(self.check("[wrong](with%20space.md#absent)"),
                         ["docs/entry.md -> with%20space.md#absent (missing fragment)"])

    def test_ignored_cache_link_is_rejected_with_or_without_local_cache(self) -> None:
        (self.root / ".gitignore").write_text(".artifacts/\n")
        text = "[local evidence](../.artifacts/report.json)"
        absent = self.check(text)
        self.assertEqual(len(absent), 1)
        self.assertIn("ignored local artifact", absent[0])
        (self.root / ".artifacts").mkdir()
        (self.root / ".artifacts/report.json").write_text("{}")
        self.assertEqual(self.check(text), absent)
        self.assertEqual(self.check("Local evidence path: `../.artifacts/report.json`"), [])

    def test_tracked_target_and_untracked_document_are_valid(self) -> None:
        (self.root / ".gitignore").write_text(".artifacts/\n")
        (self.root / ".artifacts").mkdir()
        (self.root / ".artifacts/tracked.md").write_text("# Tracked\n")
        subprocess.run(["git", "add", "-f", ".artifacts/tracked.md"], cwd=self.root, check=True, capture_output=True)
        self.assertEqual(self.check("[tracked](../.artifacts/tracked.md#tracked)"), [])

    def test_ignore_classification_failure_cannot_pass_silently(self) -> None:
        with patch("script.document_links.subprocess.run", return_value=subprocess.CompletedProcess([], 128, "", "bad git state")):
            with self.assertRaisesRegex(RuntimeError, "bad git state"):
                self.check("[target](target.md)")
