#!/usr/bin/env python3
"""Real QuickJS image.font state; native text transactions remain independent."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from .scene_vector_vm_test_support import C_SOURCES, QUICKJS, ROOT, VM


class SceneQuickJSImageFontStateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        clang = shutil.which("clang")
        if clang is None:
            raise unittest.SkipTest("clang is required for real QuickJS execution")
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-image-font-")
        cls.work = Path(cls.temporary.name)
        cls.binary = cls.work / "image-font-state"
        fixture = ROOT / "script/tests/fixtures/SceneImageFontStateQuickJSCases.c"
        # Optional fixed old-source input permits a semantic RED without
        # reverting shared product files. QuickJSNG itself stays unchanged.
        source_root = Path(os.environ.get("MWX_SCENE_IMAGE_FONT_SOURCE_ROOT", VM))
        sources = [
            source_root / source.relative_to(VM)
            if source.parent == VM else source
            for source in C_SOURCES
        ]
        inputs = [*sources, fixture, *source_root.glob("*.h")]
        cls.hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
        # Count entries into the real copy helper without changing its decisions.
        snapshot = source_root / "SceneQuickJSLayerSnapshotHost.c"
        marker = "static char *copy_snapshot_string(const char *source, size_t length) {"
        contents = snapshot.read_text(encoding="utf-8")
        if contents.count(marker) != 1:
            cls.temporary.cleanup()
            raise AssertionError("snapshot string-copy probe entry is ambiguous")
        observed_snapshot = cls.work / snapshot.name
        observed_snapshot.write_text(contents.replace(
            marker, "size_t mwx_test_snapshot_string_copies;\n\n" + marker
            + "\n    ++mwx_test_snapshot_string_copies;", 1), encoding="utf-8")
        sources = [observed_snapshot if source == snapshot else source for source in sources]
        command = [clang, "-std=c11", "-O0", "-I", str(source_root),
                   "-I", str(VM), "-I", str(QUICKJS), *map(str, sources),
                   str(fixture), "-lm", "-o", str(cls.binary)]
        compiled = subprocess.run(command, cwd=ROOT, capture_output=True,
                                  text=True, timeout=120)
        if compiled.returncode:
            cls.temporary.cleanup()
            raise AssertionError(compiled.stdout + compiled.stderr)
        print(json.dumps({"imageFontSourceRoot": str(source_root),
                          "sourceCount": len(sources), "sourceSHA256": cls.hashes},
                         sort_keys=True))

    @classmethod
    def tearDownClass(cls) -> None:
        try:
            drift = [name for name, before in cls.hashes.items()
                     if hashlib.sha256(Path(name).read_bytes()).hexdigest() != before]
            if drift:
                raise AssertionError(f"QuickJS inputs changed: {drift}")
        finally:
            cls.temporary.cleanup()

    def run_group(self, group: str) -> None:
        result = subprocess.run([str(self.binary), group], cwd=ROOT,
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["group"], group)
        self.assertEqual(report["failures"], 0, report)
        self.assertGreater(report["checks"], 0)
        print(result.stdout, end="")

    def test_shared_state_renames_and_equivalent_paths(self) -> None:
        self.run_group("shared")

    def test_callback_failure_and_late_native_discard_do_not_rollback_image_state(self) -> None:
        self.run_group("transactions")

    def test_native_snapshot_commit_abort_and_rollback_preserve_image_state(self) -> None:
        self.run_group("snapshots")

    def test_retirement_destroy_stale_and_rebuilt_domains_do_not_alias(self) -> None:
        self.run_group("lifecycle")

    def test_strict_string_paths_and_utf8_byte_boundaries(self) -> None:
        self.run_group("validation")

    def test_capability_bits_and_existing_text_authority(self) -> None:
        self.run_group("capabilities")


if __name__ == "__main__":
    unittest.main()
