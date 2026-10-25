"""Publish real captured metadata via durable mapping, SQLite WAL and exclusive rename."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tempfile
import unittest

from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


class LibraryCollectionsPublicationTests(unittest.TestCase):
    def test_publication_retry_identity_and_existing_final_preservation(self):
        paths = ["MyWallpaperX/Models/VideoWallpaper.swift", "MyWallpaperX/Models/WallpaperIndexStartupChanges.swift",
                 "MyWallpaperX/Models/WallpaperReference.swift", "MyWallpaperX/Core/LibraryCollections/LegacyLibrarySnapshot.swift",
                 "MyWallpaperX/Core/LibraryCollections/LibraryCollectionsMigration.swift",
                 "MyWallpaperX/Core/LibraryCollections/UserCollectionsStore.swift",
                 "MyWallpaperX/Core/LibraryCollections/LibraryCollectionsMigrationPublication.swift",
                 "script/tests/fixtures/LibraryCollectionsPublicationHarness.swift"]
        identities = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths}
        with tempfile.TemporaryDirectory(prefix="mwx-collections-publication-", dir="/private/tmp") as directory:
            work = Path(directory)
            for path in paths:
                shutil.copy2(ROOT / path, work / Path(path).name)
            # Instrument only the filesystem leaf in the isolated test copy.
            # The checked-in publication, transaction and retry bodies stay intact.
            publication = work / "LibraryCollectionsMigrationPublication.swift"
            source = publication.read_text()
            leaf = "guard fsync(descriptor) == 0"
            self.assertEqual(source.count(leaf), 1)
            publication.write_text(source.replace(leaf,
                "guard PublicationFsyncFault.shared.sync(descriptor, directory: url) == 0"))
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library",
                *[str(work / Path(p).name) for p in paths], "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            for mode in ["publish", "view-preferences", "fractional-date", "checkpoint-retry", "bad-final", "future-final", "empty-final", "foreign-final",
                         "conflicting-final", "lock", "lost-mapping", "bad-recovery-input", "bad-recovery-map", "fsync-retry"]:
                with self.subTest(mode=mode):
                    case = work / mode
                    case.mkdir()
                    migration = case / "migration"
                    migration.mkdir()
                    (case / "sil.json").write_text(json.dumps([
                        {"id": "image", "path": "/offline/image.png", "title": "Image", "tags": ["Shared"]}
                    ], sort_keys=True))
                    final = migration / "relations.sqlite3"
                    if mode == "bad-final":
                        final.write_bytes(b"not a SQLite database")
                    elif mode == "empty-final":
                        final.write_bytes(b"")
                    elif mode in ["future-final", "foreign-final"]:
                        with sqlite3.connect(final) as connection:
                            if mode == "future-final":
                                connection.execute("PRAGMA user_version=99")
                            else:
                                connection.execute("CREATE TABLE foreign_data(value TEXT)")
                        connection.close()
                    lock = None
                    if mode == "lock":
                        lock = (migration / "publication.lock").open("w")
                        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
                    try:
                        run = subprocess.run([str(binary), str(case), mode],
                            env=dict(os.environ, HOME=str(case), CFFIXED_USER_HOME=str(case)),
                            capture_output=True, text=True, timeout=40)
                        self.assertEqual(run.returncode, 0, mode + "\n" + run.stdout + run.stderr)
                        checks = json.loads(run.stdout)
                        self.assertTrue(checks)
                        for name, passed in checks.items():
                            self.assertIs(passed, True, mode + ": " + name + "\n" + run.stdout)
                        print(json.dumps({"mode": mode, "checks": checks}, sort_keys=True))
                    finally:
                        if lock:
                            fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
                            lock.close()
            self.assertEqual(identities, {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths})


if __name__ == "__main__":
    unittest.main()
