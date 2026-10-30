"""Actual explicit source unlink queue/receipts and still-live missing-index purge.

No App/window/runtime or user media. The original unlink body is paused at its
admission/durability boundaries; real final unlink, epochs, identity and receipts run.
Retired index-only UI deletion is not preserved as a test-only product API.
"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration

ROOT = Path(__file__).resolve().parents[2]


class VideoRemovalReceiptsTests(unittest.TestCase):
    def test_explicit_source_receipts_and_live_purge_preserve_identity(self):
        removal = ROOT / "MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+Removal.swift"
        support = ROOT / "MyWallpaperX/Modules/VideoLibrary/Core/WallpaperLibrarySupport.swift"
        model = ROOT / "MyWallpaperX/Models/VideoWallpaper.swift"
        fixture = ROOT / "script/tests/fixtures/VideoRemovalReceiptsHarness.swift"
        runtime = ROOT / "MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+RuntimeSwitching.swift"
        images = ROOT / "MyWallpaperX/Modules/StaticImageLibrary/Core/SILService.swift"
        shared = [ROOT / "MyWallpaperX" / p for p in (
            "Models/WallpaperReference.swift", "Models/WallpaperSourceImportResult.swift",
            "Shared/WallpaperSourceFileDeletion.swift", "Core/PlaybackControl/WallpaperRuntimeSwitch.swift",
            "Core/PlaybackControl/PlaybackSwitchTransaction.swift")]
        source = removal.read_text()
        methods = "\n".join(declaration(source, signature) for signature in (
            "    struct RemovalRecord", "    func enqueueDeletionTask(",
            "    @discardableResult\n    func removeDerivedAssets(", "    func purgeMissingIndexedWallpapersFromLibrary(", "    func applyLibraryRemoval(",
            "    func clearCurrentWallpaperReference(", "    func stopCurrentPlayback(",
            "    func removalRecord(", "    private func removeFileIfExists(",
            "    func deleteSourceFiles(", "    func isLocalSourceFileInUse("))
        boundary = "                let key = Data(request.url.path.utf8)"
        if methods.count(boundary) != 1: raise AssertionError("Video final admission boundary must be unique")
        methods = methods.replace(boundary, "                PhysicalFileProbe.shared.beforeAdmission(request.url)\n" + boundary)
        methods += "\n" + declaration(runtime.read_text(), "    enum RuntimeSwitchSelection")
        value_types = declaration(support.read_text(), "struct WallpaperDeletionFailure")
        body = fixture.read_text().replace("// ACTUAL_REMOVAL_METHODS", methods).replace("// ACTUAL_RESULT_TYPES", value_types)
        image_delete = declaration(images.read_text(), "    func deleteSourceFiles(")
        if image_delete.count(boundary) != 1: raise AssertionError("Image final admission boundary must be unique")
        image_delete = image_delete.replace(boundary, "                PhysicalFileProbe.shared.beforeAdmission(request.url)\n" + boundary)
        body = body.replace("// ACTUAL_IMAGE_SOURCE_DELETE", image_delete)
        inputs = [Path(__file__).resolve(), removal, support, model, fixture, runtime, images, *shared]
        hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
        with tempfile.TemporaryDirectory(prefix="mwx-video-removal-", dir="/private/tmp") as directory:
            work = Path(directory)
            frozen_model = work / model.name; shutil.copy2(model, frozen_model)
            harness = work / "Checks.swift"; harness.write_text(body)
            deletion_path = next(p for p in shared if p.name == "WallpaperSourceFileDeletion.swift")
            deletion_source = deletion_path.read_text()
            unlink = "    static func unlinkPrepared(_ prepared: Prepared) -> Outcome {"
            synchronization = "    static func synchronizeDirectory(after prepared: Prepared) -> Outcome {"
            if deletion_source.count(unlink) != 1 or deletion_source.count(synchronization) != 1:
                raise AssertionError("Actual unlink/durability boundaries must be unique")
            observed_deletion = work / deletion_path.name
            observed_deletion.write_text(deletion_source.replace(unlink,
                unlink + "\n        PhysicalFileProbe.shared.beforeUnlink(prepared.url)").replace(synchronization,
                synchronization + "\n        PhysicalFileProbe.shared.beforeSynchronization(prepared.url)"))
            actual_shared = [observed_deletion if p == deletion_path else p for p in shared]
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(frozen_model), *map(str, actual_shared), str(harness),
                "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary), str(work)], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, run.stdout + run.stderr)
            print(json.dumps(checks, sort_keys=True))
        self.assertEqual(hashes, {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs})


if __name__ == "__main__": unittest.main()
