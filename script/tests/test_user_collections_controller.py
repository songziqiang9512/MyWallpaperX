"""Serialize real relation commands, success metadata and reset barriers."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


class UserCollectionsControllerTests(unittest.TestCase):
    def test_atomic_ui_commands_history_fifo_and_reset(self):
        paths = ["MyWallpaperX/Models/WallpaperReference.swift",
                 "MyWallpaperX/Core/LibraryCollections/UserCollectionsStore.swift",
                 "MyWallpaperX/Core/LibraryCollections/UserCollectionsController.swift",
                 "script/tests/fixtures/UserCollectionsControllerHarness.swift"]
        identities = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths}
        with tempfile.TemporaryDirectory(prefix="mwx-collections-controller-", dir="/private/tmp") as directory:
            work = Path(directory)
            for path in paths:
                shutil.copy2(ROOT / path, work / Path(path).name)
            store_path = work / 'UserCollectionsStore.swift'
            source = store_path.read_text()
            actor_marker = 'actor UserCollectionsStore {'
            snapshot_marker = '    func snapshot() throws -> UserCollectionsSnapshot {'
            self.assertEqual(source.count(actor_marker), 1, actor_marker)
            self.assertEqual(source.count(snapshot_marker), 1, snapshot_marker)
            source = source.replace(actor_marker, actor_marker + '\n    nonisolated(unsafe) static var snapshotReadCount = 0', 1)
            store_path.write_text(source.replace(snapshot_marker, snapshot_marker + '\n        Self.snapshotReadCount += 1', 1))
            controller_path = work / 'UserCollectionsController.swift'
            source = controller_path.read_text()
            class_marker = '@MainActor final class UserCollectionsController: ObservableObject {'
            aliases_marker = '        let targets = Dictionary(uniqueKeysWithValues: aliases.map { ($0.alias, $0.canonical) })'
            self.assertEqual(source.count(class_marker), 1, class_marker)
            self.assertEqual(source.count(aliases_marker), 1, aliases_marker)
            source = source.replace(class_marker, class_marker + '\n    static var aliasDerivationCount = 0', 1)
            controller_path.write_text(source.replace(aliases_marker, '        Self.aliasDerivationCount += 1\n' + aliases_marker, 1))
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library",
                *[str(work / Path(p).name) for p in paths], "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary), str(work / "relations.sqlite3")], capture_output=True, text=True, timeout=40)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks)
            for name, passed in checks.items():
                self.assertIs(passed, True, name)
            print(json.dumps(checks, sort_keys=True))
            self.assertEqual(identities, {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths})


if __name__ == "__main__":
    unittest.main()
