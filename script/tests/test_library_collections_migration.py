"""Real metadata-to-relationship migration outputs, including failure/retry inputs."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


def reference(value):
    return value["provider"], value["sourceID"]


class LibraryCollectionsMigrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-collections-migration-", dir="/private/tmp")
        cls.directory = Path(cls.temporary.name)
        cls.binary = cls.directory / "migration"
        sources = [
            ROOT / "MyWallpaperX/Models/WallpaperReference.swift",
            ROOT / "MyWallpaperX/Core/LibraryCollections/LibraryCollectionsMigration.swift",
            ROOT / "script/tests/fixtures/LibraryCollectionsMigrationHarness.swift",
        ]
        result = subprocess.run(
            ["xcrun", "swiftc", "-parse-as-library", *map(str, sources),
             "-module-cache-path", str(cls.directory / "modules"), "-o", str(cls.binary)],
            capture_output=True, text=True, timeout=120,
        )
        if result.returncode:
            cls.temporary.cleanup()
            raise AssertionError(result.stdout + result.stderr)
        cls.home = cls.directory / "home"
        cls.home.mkdir()

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def run_scenario(self, scenario, *arguments):
        result = subprocess.run(
            [str(self.binary), scenario, *map(str, arguments)],
            env=dict(os.environ, HOME=str(self.home), CFFIXED_USER_HOME=str(self.home)),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return json.loads(result.stdout)

    def test_same_name_normalization_order_and_orphan_tags(self):
        result = self.run_scenario("mixed")
        payload = result["payload"]
        self.assertEqual([p["name"] for p in payload["playlists"]],
                         ["A", "Café", "Empty", "UPPER", "case", "Image", "Case", "orphanVideo", "orphanImage"])
        self.assertEqual([p["sidebarRank"] for p in payload["playlists"]], list(range(9)))
        self.assertEqual(len({p["id"] for p in payload["playlists"]}), 9)
        by_name = {p["name"]: p["id"] for p in payload["playlists"]}
        members = sorted((m for m in payload["members"] if m["playlistID"] == by_name["A"]),
                         key=lambda m: m["position"])
        self.assertEqual([reference(m["reference"]) for m in members],
                         [("steamWorkshop", "video:雪山.movie"), ("videoLibrary", "42"),
                          ("staticImageLibrary", "42")])
        self.assertEqual([m["position"] for m in members], [0, 1, 2])
        self.assertEqual([m for m in payload["members"] if m["playlistID"] == by_name["Empty"]], [])
        origins = {m["normalizedName"]: m["origins"] for m in result["manifest"]["tagMappings"]}
        self.assertTrue(any(o["originalName"] == "Cafe\u0301" for o in origins["Café"]))
        self.assertTrue(all(not o["isDeclared"] for o in origins["orphanVideo"]))
        self.assertEqual(result["counts"]["orphanTags"], 2)

    def test_alias_favorites_recent_and_offline_recovery_hints(self):
        payload = self.run_scenario("mixed")["payload"]
        self.assertEqual([reference(f["reference"]) for f in payload["favorites"]],
                         [("steamWorkshop", "video:雪山.movie"), ("videoLibrary", "42")])
        self.assertTrue(all("favoritedAt" not in f for f in payload["favorites"]))
        self.assertEqual([f["migrationOrder"] for f in payload["favorites"]], [0, 1])
        self.assertEqual([reference(r["reference"]) for r in payload["recent"]],
                         [("steamWorkshop", "video:雪山.movie"), ("staticImageLibrary", "42"),
                          ("pixabay", "42"), ("steamWorkshop", "42")])
        self.assertTrue(all("lastSuccessfulUseAt" not in r for r in payload["recent"]))
        self.assertEqual([r["commitSequence"] for r in payload["recent"]], [4, 3, 2, 1])
        self.assertEqual([r["migrationOrder"] for r in payload["recent"]], [0, 1, 2, 3])
        self.assertEqual([reference(a["canonical"]) for a in payload["aliases"]],
                         [("steamWorkshop", "video:雪山.movie")] * 2)
        locators = {reference(l["reference"]): l["locator"] for l in payload["locators"]}
        self.assertEqual(locators[("videoLibrary", "backing-one")]["path"],
                         "/disconnected/volume/first.mp4")
        self.assertEqual(locators[("steamWorkshop", "video:雪山.movie")]["path"],
                         "/disconnected/volume/first.mp4")
        self.assertEqual(locators[("staticImageLibrary", "42")]["path"],
                         "/disconnected/volume/still.heic")
        self.assertIn(("pixabay", "42"), locators)

    def test_saved_manifest_retries_in_a_new_process_without_new_ids(self):
        self.run_scenario("prepare", self.directory)
        before = json.loads((self.directory / "before.json").read_text())
        after = self.run_scenario("resume", self.directory)
        self.assertEqual(after, before)
        self.assertEqual(self.run_scenario("recapture", self.directory), before)

    def test_empty_fallback_preserves_explicit_empty_playlist(self):
        result = self.run_scenario("empty")
        self.assertEqual([p["name"] for p in result["payload"]["playlists"]], ["Empty"])
        for field in ("members", "favorites", "recent", "locators", "aliases"):
            self.assertEqual(result["payload"][field], [])
        self.assertEqual(result["counts"]["videos"], 0)

    def test_recent_deduplicates_before_limiting_and_retains_unknown_time(self):
        result = self.run_scenario("recent")
        rows = result["payload"]["recent"]
        self.assertEqual([reference(r["reference"]) for r in rows],
                         [("pixabay", str(i)) for i in range(50)])
        self.assertEqual([r["commitSequence"] for r in rows], list(range(50, 0, -1)))
        self.assertTrue(all("lastSuccessfulUseAt" not in r for r in rows))

    def test_invalid_alias_graph_or_manifest_never_returns_partial_import(self):
        self.assertEqual(self.run_scenario("failures"), {
            "cycle": "aliasCycle", "selfAlias": "aliasCycle", "conflict": "conflictingAlias",
            "emptyReference": "invalidReference", "emptyName": "invalidTagName",
            "wrongSnapshot": "manifestMismatch", "changedTags": "manifestMismatch",
            "duplicateUUID": "manifestMismatch", "unknownSchema": "manifestMismatch",
        })


if __name__ == "__main__":
    unittest.main()
