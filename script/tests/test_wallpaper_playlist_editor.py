"""Real native playlist Editor, image preparation, and SQLite publication.

The unchanged Editor and its private file-level image preparer share a frozen
file with the harness. No product visibility or behavior is altered for tests.
Native file selection is opened and cancelled; prepared image bytes, metadata,
default/cancel controls, permission changes and late reads use real owners.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.native_app_harness import prepare_native_app, run_native_app
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


class WallpaperPlaylistEditorTests(unittest.TestCase):
    def test_native_editor_draft_save_cancel_cover_and_revocation(self):
        paths = [ROOT / "MyWallpaperX" / name for name in (
            "Models/WallpaperReference.swift", "Core/LibraryCollections/UserCollectionsStore.swift",
            "Core/LibraryCollections/UserCollectionsController.swift",
            "Shared/Components/WallpaperLibrarySymbols.swift", "Shared/Components/WallpaperLibraryControlStyle.swift",
            "Shared/Components/WallpaperFormFieldStyle.swift",
            "Shared/UI/ListThumbnailTintSource.swift", "Shared/UI/WallpaperLibrarySheetPresentation.swift",
            "Shared/UI/ModalPresentation.swift")]
        native = ROOT / "script/tests/fixtures/NativeAppHarness.swift"
        editor = Path(os.environ.get("MWX_PLAYLIST_EDITOR_SOURCE",
            ROOT / "MyWallpaperX/Shell/WallpaperPlaylistEditorController.swift")).resolve()
        harness = ROOT / "script/tests/fixtures/WallpaperPlaylistEditorHarness.swift"
        observed = paths + [native, editor, harness, Path(__file__), ROOT / "script/tests/native_app_harness.py",
                            ROOT / "script/tests/test_video_thumbnail_prefetch.py"]
        hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed}
        with tempfile.TemporaryDirectory(prefix="mwx-playlist-editor-", dir="/private/tmp") as directory:
            work = Path(directory)
            sources = []
            input_checks = ROOT / "script/tests/fixtures/WallpaperLibraryModalInputChecks.swift"
            hashes[str(input_checks)] = hashlib.sha256(input_checks.read_bytes()).hexdigest()
            observed.append(input_checks)
            for path in paths + [native, input_checks]:
                target = work / path.name
                shutil.copy2(path, target)
                sources.append(str(target))
            checks_source = work / "EditorChecks.swift"
            checks_source.write_text(editor.read_text() + "\n" + harness.read_text())
            binary = prepare_native_app(work, "WallpaperPlaylistEditor")
            build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library",
                *sources, str(checks_source), "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = run_native_app(binary, (str(work),), timeout=60)
            diagnostic = f"LaunchServices={run.launch_returncode}\nstdout:\n{run.stdout}\nstderr:\n{run.stderr}"
            self.assertEqual(run.launch_returncode, 0, diagnostic)
            self.assertTrue(run.stdout.strip(), diagnostic)
            try:
                checks = json.loads(run.stdout)
            except json.JSONDecodeError as error:
                self.fail(f"Editor native result missing: {error}\n{diagnostic}")
            self.assertGreaterEqual(len(checks), 25)
            print(json.dumps(checks, sort_keys=True))
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertIs(passed, True, diagnostic)
            if output := os.environ.get("MWX_COLLECTIONS_PROOF_DIR"):
                proof = Path(output); proof.mkdir(parents=True, exist_ok=True)
                (proof / "playlist-editor-inputs.json").write_text(json.dumps(hashes, indent=2) + "\n")
                (proof / "playlist-editor-report.json").write_text(json.dumps(checks, indent=2) + "\n")
                (proof / "playlist-editor-build.log").write_text(build.stdout + build.stderr)
                (proof / "playlist-editor-runtime.log").write_text(run.stderr)
        self.assertEqual(hashes, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed})


if __name__ == "__main__":
    unittest.main()
