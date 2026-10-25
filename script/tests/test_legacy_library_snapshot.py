"""Exercise pre-cleanup capture with a real uncheckpointed SQLite WAL and raw JSON."""
from contextlib import closing
import json
from pathlib import Path
import os
import sqlite3
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LegacyLibrarySnapshotTests(unittest.TestCase):
    def test_frozen_inputs_wal_backup_ordered_journal_and_failure_boundaries(self):
        with tempfile.TemporaryDirectory(prefix="mwx-legacy-capture-", dir="/private/tmp") as directory:
            work = Path(directory)
            binary = work / "checks"
            paths = [
                "MyWallpaperX/Models/VideoWallpaper.swift",
                "MyWallpaperX/Models/WallpaperIndexStartupChanges.swift",
                "MyWallpaperX/Models/WallpaperReference.swift",
                "MyWallpaperX/Core/LibraryCollections/LibraryCollectionsMigration.swift",
                "MyWallpaperX/Core/LibraryCollections/LegacyLibrarySnapshot.swift",
                "script/tests/fixtures/LegacyLibrarySnapshotHarness.swift",
            ]
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "5",
                "-default-isolation", "MainActor", *[str(ROOT / p) for p in paths],
                "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            for mode in ["journal", "fallback-empty", "fallback-nonempty", "missing-index", "bad-journal",
                         "bad-fallback", "bad-tags", "bad-image", "bad-db", "bad-db-tags", "wrong-defaults-type",
                         "fresh", "initialized-empty", "fallback-bad-journal", "bad-permission",
                         "fallback-bad-db-tags", "fallback-bad-db", "fallback-unreadable", "frozen-auxiliary", "view-preferences"]:
                with self.subTest(mode=mode):
                    if mode in ["bad-permission", "fallback-unreadable"] and os.geteuid() == 0:
                        continue  # Root bypasses POSIX access checks.
                    case = work / mode
                    case.mkdir()
                    home = case / "home"
                    home.mkdir()
                    image_data = [{"id": "image-missing", "path": "/offline/image.png", "title": "Offline",
                                   "tags": ["Image empty", "Unlisted"]}]
                    if mode == "view-preferences":
                        image_data = [{"id": name, "path": "/offline/" + name + ".png", "title": name, "tags": []}
                                      for name in ["image-late", "image-unknown", "image-early", "image-malformed"]]
                        image_data[0]["lastUsed"] = 20
                        image_data[2]["lastUsed"] = 10
                        image_data[3]["lastUsed"] = "unreadable optional old clock"
                    if mode != "fresh":
                        (case / "sil.json").write_text("bad" if mode == "bad-image" else json.dumps(image_data))
                    connection = None
                    if mode in ["bad-db", "fallback-bad-db"]:
                        (case / "index.sqlite3").write_bytes(b"not a database")
                        if mode == "fallback-bad-db":
                            (case / "index.sqlite3-wal").write_bytes(b"unreadable wal recovery")
                            (case / "index.sqlite3-shm").write_bytes(b"unreadable shm recovery")
                    elif mode not in ["missing-index", "fresh"]:
                        source_index = case / "index.sqlite3"
                        if mode in ["bad-permission", "fallback-unreadable"]:
                            (case / "locked").mkdir()
                            source_index = case / "locked/index.sqlite3"
                        connection = sqlite3.connect(source_index)
                        connection.execute("PRAGMA journal_mode=WAL")
                        connection.execute("PRAGMA wal_autocheckpoint=0")
                        connection.executescript("""
                            CREATE TABLE wallpapers(sort_index INTEGER NOT NULL,id TEXT PRIMARY KEY,
                              title TEXT NOT NULL,path TEXT NOT NULL,is_favorite INTEGER NOT NULL,
                              last_used REAL NOT NULL,tags_json TEXT NOT NULL);
                            CREATE TABLE meta(key TEXT PRIMARY KEY,value TEXT NOT NULL);
                            INSERT INTO meta VALUES('library_initialized','1');
                        """)
                        connection.executemany("INSERT INTO wallpapers VALUES(?,?,?,?,?,?,?)", [
                            (0, "one", "One", "/offline/one.mp4", 1, 100, "broken" if mode in ["bad-db-tags", "fallback-bad-db-tags"] else '["A","Keep"]'),
                            (1, "two", "Two", "/offline/two.mp4", 0, 90, '[]'),
                        ])
                        if mode == "initialized-empty":
                            connection.execute("DELETE FROM wallpapers")
                        connection.commit()
                        self.assertTrue(Path(str(source_index) + "-wal").stat().st_size > 0)
                    if mode in ["bad-permission", "fallback-unreadable"]:
                        (case / "locked").chmod(0)
                    try:
                        run = subprocess.run([str(binary), str(case), mode],
                            env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                            capture_output=True, text=True, timeout=30)
                        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                        checks = json.loads(run.stdout)
                        self.assertTrue(checks)
                        for name, passed in checks.items():
                            self.assertTrue(passed, mode + ": " + name + "\n" + run.stdout)
                        if mode in ["journal", "fallback-empty", "fallback-nonempty"]:
                            # Read the backup alone: no copied -wal/-shm is needed.
                            with closing(sqlite3.connect(case / "backup/wallpaper_index.sqlite3")) as copied:
                                self.assertEqual(copied.execute("SELECT id FROM wallpapers ORDER BY sort_index").fetchall(),
                                                 [("one",), ("two",)])
                            self.assertFalse((case / "backup/wallpaper_index.sqlite3-wal").exists())
                        if mode in ["bad-db-tags", "fallback-bad-db-tags"]:
                            with closing(sqlite3.connect(case / "backup/wallpaper_index.sqlite3")) as raw:
                                self.assertEqual(raw.execute("SELECT tags_json FROM wallpapers WHERE id='one'").fetchone(), ("broken",))
                        if mode == "fallback-bad-db":
                            self.assertEqual((case / "backup/wallpaper_index.sqlite3.raw").read_bytes(), b"not a database")
                            self.assertEqual((case / "backup/wallpaper_index.sqlite3.raw-wal").read_bytes(), b"unreadable wal recovery")
                            self.assertEqual((case / "backup/wallpaper_index.sqlite3.raw-shm").read_bytes(), b"unreadable shm recovery")
                        print(json.dumps({"mode": mode, "checks": checks}, sort_keys=True))
                    finally:
                        if mode in ["bad-permission", "fallback-unreadable"]:
                            (case / "locked").chmod(0o700)
                        if connection is not None:
                            connection.close()


if __name__ == "__main__":
    unittest.main()
