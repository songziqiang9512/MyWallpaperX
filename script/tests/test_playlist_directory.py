"""Native directory layout, item selection, and fixed-UUID menu/keyboard actions."""
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
from script.tests.test_ui_library_algorithms import declaration

ROOT = Path(__file__).resolve().parents[2]


class PlaylistDirectoryTests(unittest.TestCase):
    def test_native_directory_interactions(self):
        paths = ["MyWallpaperX/Models/WallpaperReference.swift",
                 "MyWallpaperX/Shared/UI/WallpaperPlaylistArtwork.swift",
                 "MyWallpaperX/Models/WallpaperLibraryPage.swift",
                 "MyWallpaperX/Core/LibraryCollections/UserCollectionsStore.swift",
                 "MyWallpaperX/Core/LibraryCollections/UserCollectionsController.swift",
                 "MyWallpaperX/Shared/Components/WallpaperLibraryGridMetrics.swift",
                 "MyWallpaperX/Shared/Components/WallpaperLibrarySymbols.swift",
                 "MyWallpaperX/Shared/Components/WallpaperLibraryControlStyle.swift",
                 "MyWallpaperX/Shared/UI/ListThumbnailTintSource.swift",
                 "MyWallpaperX/Shell/AppKitListBackgroundTint.swift",
                 "MyWallpaperX/Shell/WallpaperPlaylistEditorController.swift",
                 "MyWallpaperX/Shared/Components/WallpaperFormFieldStyle.swift",
                 "MyWallpaperX/Shared/UI/ModalPresentation.swift",
                 "MyWallpaperX/Shared/UI/WallpaperLibrarySheetPresentation.swift",
                 "MyWallpaperX/Shared/UI/WallpaperArtworkDemandObservation.swift",
                 "MyWallpaperX/Shared/UI/WallpaperGridScrollView.swift",
                 "MyWallpaperX/Shell/AppKitPlaylistDirectoryController.swift",
                 "MyWallpaperX/Shell/AppKitDetailHostViewController.swift",
                 "MyWallpaperX/Shell/PlaylistOrganizationActions.swift",
                 "MyWallpaperX/Shell/WallpaperPlaylistCreationNotice.swift",
                 "script/tests/fixtures/NativeAppHarness.swift",
                 "script/tests/fixtures/PlaylistDirectoryReorderChecks.swift",
                 "script/tests/fixtures/PlaylistDirectoryAnimationChecks.swift",
                 "script/tests/fixtures/PlaylistDirectoryHarness.swift"]
        directory = "MyWallpaperX/Shell/AppKitPlaylistDirectoryController.swift"
        selected = {path: ROOT / path for path in paths}
        override = os.environ.get("MWX_PLAYLIST_DIRECTORY_SOURCE")
        if override:
            candidate = Path(override).expanduser()
            selected[directory] = (candidate if candidate.is_absolute() else ROOT / candidate).resolve()
        self.assertTrue(selected[directory].is_file(), str(selected[directory]))
        observed = list(selected.values()) + [Path(__file__).resolve(),
            ROOT / "script/tests/test_ui_library_algorithms.py",
            ROOT / "script/tests/test_video_thumbnail_prefetch.py", ROOT / "script/tests/native_app_harness.py"]

        def input_hashes():
            return {str(path.resolve()): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed}

        proof = None
        if destination := os.environ.get("MWX_PLAYLIST_DIRECTORY_PROOF_DIR"):
            proof = Path(destination).expanduser().resolve()
            proof.mkdir(parents=True, exist_ok=True)

        def record(name, value):
            if proof is not None:
                (proof / name).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")

        identities = input_hashes()
        directory_receipt = {"path": str(selected[directory].resolve()),
            "sha256": identities[str(selected[directory].resolve())], "override": bool(override)}
        record("inputs.json", {"directory_source": directory_receipt, "identities": identities})
        print("PlaylistDirectory source: " + json.dumps(directory_receipt, sort_keys=True), flush=True)

        def check_frozen_inputs():
            after = input_hashes()
            record("inputs-final.json", {"identities": after, "unchanged": identities == after})
            self.assertEqual(identities, after)

        # Negative controls deliberately fail a behavior assertion; input drift
        # must still be checked and recorded after that failure.
        self.addCleanup(check_frozen_inputs)
        with tempfile.TemporaryDirectory(prefix="mwx-playlist-directory-", dir="/private/tmp") as folder:
            work = Path(folder)
            sources = []
            for path in paths:
                target = work / Path(path).name
                shutil.copy2(selected[path], target)
                if target.name == "AppKitPlaylistDirectoryController.swift":
                    # Expose only the real private item type inside this frozen
                    # test copy, so reuse checks call its production configure.
                    source = target.read_text()
                    marker = "private final class PlaylistDirectoryItem:"
                    self.assertEqual(source.count(marker), 1)
                    source = source.replace(marker, "final class PlaylistDirectoryItem:", 1)
                    motion = "NSWorkspace.shared.accessibilityDisplayShouldReduceMotion"
                    self.assertEqual(source.count(motion), 1)
                    source = source.replace(motion, "PlaylistDirectoryAnimationProbe.reduceMotion", 1)
                    reload = "            collection.reloadData()"
                    self.assertEqual(source.count(reload), 1)
                    source = source.replace(reload, "            PlaylistDirectoryAnimationProbe.reloads += 1\n" + reload, 1)
                    # Keep the real native batch and both production closure
                    # bodies; the fixture can delay delivery of a callback that
                    # AppKit has actually invoked, independently of OS timing.
                    callback = declaration(source, "completionHandler:")
                    self.assertEqual(source.count(callback), 1)
                    self.assertTrue(callback.startswith("completionHandler: {"))
                    body = callback.removeprefix("completionHandler: ")
                    wrapped = "completionHandler: PlaylistDirectoryBatchCompletionProbe.wrap(" + body + ")"
                    source = source.replace(callback, wrapped, 1)
                    target.write_text(source)
                    record("directory-test-copy.json", {"selected_source": directory_receipt,
                        "private_item_exposed": True, "test_only_completion_delivery": True,
                        "controlled_reduce_motion_leaf": True, "reload_observation_only": True,
                        "original_callback_sha256": hashlib.sha256(callback.encode()).hexdigest(),
                        "unchanged_callback_body_sha256": hashlib.sha256(body.encode()).hexdigest(),
                        "wrapped_callback_sha256": hashlib.sha256(wrapped.encode()).hexdigest(),
                        "compiled_copy_sha256": hashlib.sha256(source.encode()).hexdigest()})
                sources.append(str(target))
            binary = prepare_native_app(work, "PlaylistDirectory")
            command = ["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors",
                "-parse-as-library", *sources, "-module-cache-path", str(work / "modules"), "-o", str(binary)]
            record("compiled-inputs.json", {Path(path).name: hashlib.sha256(Path(path).read_bytes()).hexdigest()
                for path in sources})
            build = subprocess.run(command,
                capture_output=True, text=True, timeout=120)
            record("compile.json", {"command": command, "returncode": build.returncode,
                "stdout": build.stdout, "stderr": build.stderr})
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = run_native_app(binary, timeout=40)
            runtime = {"launch_returncode": run.launch_returncode, "stdout": run.stdout, "stderr": run.stderr}
            record("runtime.json", runtime)
            self.assertEqual(run.launch_returncode, 0, run.stdout + run.stderr)
            self.assertTrue(run.stdout.strip().startswith("{"), run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            runtime["checks"] = checks
            record("runtime.json", runtime)
            self.assertTrue(checks)
            print(json.dumps(checks, sort_keys=True))
            for name, passed in checks.items():
                self.assertIs(passed, True, name + "\n" + run.stdout + "\n" + run.stderr)


if __name__ == "__main__":
    unittest.main()
