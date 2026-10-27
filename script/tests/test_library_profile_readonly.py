"""Actual Commands/Coordinator admission with recording panel/importer leaves.

Workspace recovery projection and actual importer/profile persistence have their
own gates. This method shows no panel and writes only its owned fixture files.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


class LibraryProfileReadOnlyTests(unittest.TestCase):
    def test_recovery_organization_and_import_ui_denial(self):
        paths = [ROOT / p for p in (
            "script/tests/fixtures/LibraryProfileReadOnlyHarness.swift",
            "MyWallpaperX/App/WallpaperLibraryCommands.swift",
            "MyWallpaperX/App/WallpaperLibraryImportCoordinator.swift",
            "MyWallpaperX/Shell/WallpaperLibraryPresentation.swift",
            "MyWallpaperX/Models/WallpaperLibraryPage.swift")]
        identities = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
        fixture, commands, coordinator, presentation, page = [p.read_text() for p in paths]
        fixture = fixture.replace("// ACTUAL_LIBRARY_PAGE", declaration(page, "nonisolated enum WallpaperLibraryPage:"))
        fixture = fixture.replace("// ACTUAL_CAN_EDIT", declaration(presentation, "    var canEditCollections:"))
        fixture = fixture.replace("// ACTUAL_COMMAND_METHODS", "\n".join(declaration(commands, signature) for signature in (
            "    var canOrganize:", "    var canImport:", "    func importFiles(")))
        choice = declaration(coordinator, "    func chooseFiles(")
        self.assertEqual(choice.count("NSOpenPanel()"), 1)
        choice = choice.replace("NSOpenPanel()", "RecordingImportPanel()")
        fixture = fixture.replace("// ACTUAL_COORDINATOR_METHODS",
            declaration(coordinator, "    static func permitsImport(") + "\n" + choice)
        with tempfile.TemporaryDirectory(prefix="mwx-profile-readonly-", dir="/private/tmp") as folder:
            work = Path(folder)
            source = work / "Checks.swift"
            source.write_text(fixture)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library",
                str(source), "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120)
            retained = None
            if evidence := os.environ.get("MWX_LIBRARY_PROFILE_EVIDENCE"):
                retained = Path(evidence); retained.mkdir(parents=True, exist_ok=True)
                (retained / "Checks.swift").write_text(fixture)
                (retained / "inputs.json").write_text(json.dumps(identities, indent=2) + "\n")
                (retained / "compile.stdout").write_text(build.stdout)
                (retained / "compile.stderr").write_text(build.stderr)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / "home"; home.mkdir()
            run = subprocess.run([str(binary), str(work)], capture_output=True, text=True, timeout=20,
                env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)))
            if retained:
                (retained / "runtime.stdout").write_text(run.stdout)
                (retained / "runtime.stderr").write_text(run.stderr)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            required = {
                "recovery-command-refuses-panel-and-import-route",
                "recovery-denial-never-dispatches-worker-or-reads-host",
                "recovery-ui-denial-keeps-original-source-bytes",
                "editable-typed-urls-preserve-order-without-panel",
                "cancelled-panel-does-not-dispatch-import",
                "editable-nil-entry-dispatches-panel-selection",
                "panel-reset-epoch-rejects-late-selection",
                "panel-page-change-retains-original-target",
                "disabled-editing-refuses-command-and-coordinator",
                "reset-in-progress-refuses-command-and-coordinator",
                "undo-transaction-blocks-both-command-routes",
                "ending-undo-restores-original-command-admission",
                "unsupported-pages-never-open-panel-or-dispatch",
                "entry-tests-preserve-all-owned-source-bytes",
            }
            self.assertTrue(required.issubset(checks), checks)
            for name, passed in checks.items():
                self.assertIs(passed, True, name)
            print(json.dumps(checks, sort_keys=True))
        self.assertEqual(identities, {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths})


if __name__ == "__main__":
    unittest.main()
