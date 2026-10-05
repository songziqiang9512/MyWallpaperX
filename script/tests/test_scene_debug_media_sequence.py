#!/usr/bin/env python3
"""Run the actual debug sequence scheduler and media inbox without an App/GPU."""

from __future__ import annotations

import base64
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
DEBUG_SOURCE = ROOT / "MyWallpaperX/App/Debug/DebugScenePlaybackRunner+MediaThumbnail.swift"
INBOX_SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneMediaThumbnailInbox.swift"
STEP = re.compile(
    r"phase=media-sequence-step index=(\d+) action=(\w+) accepted=(true|false) "
    r"artGeneration=(\d+) playbackGeneration=(\d+) propertiesGeneration=(\d+) "
    r"timelineGeneration=(\d+)"
)
PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAF"
    "gAI/ScLbtAAAAABJRU5ErkJggg=="
)
HARNESS = r'''
import Foundation

@MainActor
enum DebugScenePlaybackRunner {
    static func argumentValue(after argument: String) -> String? {
        guard argument == "--mwx-debug-scene-media-thumbnail-sequence-json",
              CommandLine.arguments[1] != "absent" else { return nil }
        return try? String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
    }
}

@main
struct MediaSequenceHarness {
    @MainActor
    static func main() throws {
        let inbox = SceneMediaThumbnailInbox.shared
        if CommandLine.arguments[3] == "seed" {
            precondition(inbox.publish(Data([7, 8, 9])))
            precondition(inbox.publishMediaProperties(title: "Before", artist: "Before Artist"))
            precondition(inbox.publishPlaybackState(1))
            precondition(inbox.publishMediaTimeline(position: 3, duration: 12))
        }
        DebugScenePlaybackRunner.scheduleRequestedMediaThumbnailSequence(
            rootURL: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        let value = inbox.latest()
        let absent = NSNull()
        let result: [String: Any] = [
            "art": value.current?.base64EncodedString() as Any? ?? absent,
            "artGeneration": value.generation,
            "playbackState": value.playbackState as Any? ?? absent,
            "playbackGeneration": value.playbackGeneration,
            "properties": value.properties.map { properties -> [String: String] in
                ["title": properties.title, "artist": properties.artist,
                 "subTitle": properties.subTitle, "albumTitle": properties.albumTitle,
                 "albumArtist": properties.albumArtist, "genres": properties.genres,
                 "contentType": properties.contentType]
            } as Any? ?? absent,
            "propertiesGeneration": value.propertiesGeneration,
            "timeline": value.timeline.map { ["position": $0.position, "duration": $0.duration] }
                as Any? ?? absent,
            "timelineGeneration": value.timelineGeneration,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneDebugMediaSequenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-debug-media-sequence-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.directory = Path(cls.temporary.name)
        harness = cls.directory / "harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = cls.directory / "sequence"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(cls.directory / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(cls.directory / "swift-cache")
        compiled = subprocess.run(
            ["swiftc", "-D", "DEBUG", str(INBOX_SOURCE), str(DEBUG_SOURCE),
             str(harness), "-o", str(cls.binary)],
            cwd=ROOT, env=environment, capture_output=True, text=True,
        )
        if compiled.returncode:
            raise RuntimeError(compiled.stderr)

    def run_sequence(self, entries, *, seed=False, raw=None):
        with tempfile.TemporaryDirectory(dir=self.directory, prefix="case-") as directory:
            root = Path(directory)
            (root / "art.png").write_bytes(PNG)
            (root / "empty.png").write_bytes(b"")
            (root / "unsupported.txt").write_bytes(PNG)
            payload = root / "sequence.json"
            payload.write_text(raw if raw is not None else json.dumps(entries), encoding="utf-8")
            process = subprocess.run(
                [str(self.binary), str(payload), str(root), "seed" if seed else "empty"],
                capture_output=True, text=True, check=True, timeout=5,
            )
            steps = [
                {"index": int(index), "action": action, "accepted": accepted == "true",
                 "art": int(art), "playback": int(playback),
                 "properties": int(properties), "timeline": int(timeline)}
                for index, action, accepted, art, playback, properties, timeline
                in STEP.findall(process.stderr)
            ]
            return json.loads(process.stdout), steps, process.stderr

    def test_properties_all_fields_playback_and_timeline_use_real_channels(self):
        properties = {
            "title": "Private Track Marker", "artist": "Artist", "subTitle": "Live",
            "albumTitle": "Album", "albumArtist": "Album Artist", "genres": "Rock,Pop",
            "contentType": "music",
        }
        result, steps, log = self.run_sequence([
            {"properties": properties, "delay": 0.1},
            {"playbackState": 2, "delay": 0.1},
            {"timeline": {"position": 15.5, "duration": 10}, "delay": 0.1},
        ])
        self.assertEqual(result["properties"], properties)
        self.assertEqual(result["playbackState"], 2)
        self.assertEqual(result["timeline"], {"position": 15.5, "duration": 10})
        self.assertEqual([step["action"] for step in steps], ["properties", "playbackState", "timeline"])
        self.assertEqual([(s["properties"], s["playback"], s["timeline"]) for s in steps],
                         [(1, 0, 0), (1, 1, 0), (1, 1, 1)])
        self.assertTrue(all(step["accepted"] for step in steps))
        self.assertNotIn(properties["title"], log)
        self.assertNotIn(properties["artist"], log)

    def test_equal_delay_preserves_array_order_and_channel_dedup(self):
        result, steps, _ = self.run_sequence([
            {"properties": {"title": "A", "artist": "a"}, "delay": 0.1},
            {"properties": {"title": "B", "artist": "b"}, "delay": 0.1},
            {"properties": {"title": "B", "artist": "b"}, "delay": 0.1},
            {"playbackState": 0, "delay": 0.1},
            {"playbackState": 1, "delay": 0.1},
            {"playbackState": 2, "delay": 0.1},
            {"timeline": {"position": 1, "duration": 20}, "delay": 0.1},
            {"timeline": {"position": 2, "duration": 20}, "delay": 0.1},
        ])
        self.assertEqual([s["index"] for s in steps], list(range(8)))
        self.assertEqual([s["properties"] for s in steps[:3]], [1, 2, 2])
        self.assertEqual(result["properties"]["title"], "B")
        self.assertEqual(result["playbackGeneration"], 3)
        self.assertEqual(result["timelineGeneration"], 2)

    def test_delays_schedule_by_time_without_reordering_equal_timestamp_entries(self):
        result, steps, _ = self.run_sequence([
            {"playbackState": 2, "delay": 0.18},
            {"playbackState": 1, "delay": 0.1},
            {"timeline": {"position": 4, "duration": 8}, "delay": 0.1},
        ])
        self.assertEqual([s["index"] for s in steps], [1, 2, 0])
        self.assertEqual(result["playbackState"], 2)

    def test_legacy_path_and_clear_preserve_other_media_channels(self):
        result, steps, log = self.run_sequence([
            {"path": "art.png", "clear": False, "delay": 0.1},
            {"clear": True, "delay": 0.1},
        ], seed=True)
        self.assertEqual(result["art"], None)
        self.assertEqual(result["artGeneration"], 3)
        self.assertEqual(result["properties"]["title"], "Before")
        self.assertEqual(result["playbackState"], 1)
        self.assertEqual(result["timeline"], {"position": 3, "duration": 12})
        self.assertEqual([s["art"] for s in steps], [2, 3])
        self.assertTrue(all(s["accepted"] for s in steps))
        self.assertEqual(log.count("phase=media-thumbnail-cleared"), 1)

    def test_empty_track_requires_explicit_properties_state_and_timeline_actions(self):
        empty = [
            {"properties": {"title": "", "artist": ""}, "delay": 0.1},
            {"playbackState": 0, "delay": 0.1},
            {"timeline": {"position": 0, "duration": 0}, "delay": 0.1},
        ]
        result, steps, _ = self.run_sequence(empty, seed=True)
        self.assertEqual(result["art"], base64.b64encode(bytes([7, 8, 9])).decode())
        self.assertEqual(result["artGeneration"], 1)
        self.assertEqual(set(result["properties"].values()), {""})
        self.assertEqual(result["playbackState"], 0)
        self.assertEqual(result["timeline"], {"position": 0, "duration": 0})
        self.assertEqual([s["index"] for s in steps], [0, 1, 2])
        result, _, _ = self.run_sequence([*empty, {"clear": True, "delay": 0.1}], seed=True)
        self.assertIsNone(result["art"])

    def test_schema_errors_reject_whole_sequence_before_any_publication(self):
        invalid = [
            {}, {"clear": False}, {"path": "art.png", "clear": True},
            {"path": "art.png", "properties": {"title": "A", "artist": "B"}},
            {"properties": {"title": "A", "artist": "B"}, "playbackState": 1},
            {"clear": True, "timeline": {"position": 0, "duration": 1}},
            {"properties": {"title": "A"}}, {"properties": {"artist": "B"}},
            {"properties": None}, {"properties": {"title": 1, "artist": "B"}},
            {"properties": {"title": "A", "artist": "B", "genres": None}},
            {"properties": {"title": "A", "artist": "B", "unknown": "C"}},
            {"playbackState": None}, {"playbackState": True}, {"playbackState": "1"},
            {"playbackState": -1}, {"playbackState": 3}, {"playbackState": 0.5},
            {"timeline": None}, {"timeline": {"position": 0}},
            {"timeline": {"position": -1, "duration": 1}},
            {"timeline": {"position": 0, "duration": -1}},
            {"timeline": {"position": True, "duration": 1}},
            {"timeline": {"position": "0", "duration": 1}},
            {"timeline": {"position": 0, "duration": 1, "unknown": 2}},
            {"path": ""}, {"path": "art.png", "unknown": 1}, {"clear": "true"},
        ]
        for entry in invalid:
            with self.subTest(entry=entry):
                result, steps, log = self.run_sequence([
                    {"path": "art.png", "delay": 0.1}, {"delay": 0.1, **entry},
                ], seed=True)
                self.assertEqual(steps, [])
                self.assertIn("phase=media-sequence-rejected", log)
                self.assertEqual(result["artGeneration"], 1)
                self.assertEqual(result["properties"]["title"], "Before")
                self.assertEqual(result["playbackGeneration"], 1)
                self.assertEqual(result["timelineGeneration"], 1)

    def test_field_utf8_control_character_delay_count_and_json_bounds(self):
        for field in ["title", "artist", "subTitle", "albumTitle", "albumArtist", "genres", "contentType"]:
            for value in ["x" * 4097, "界" * 1366, "bad\nvalue", "bad\x00value"]:
                with self.subTest(field=field, kind=value[:8]):
                    properties = {"title": "A", "artist": "B", field: value}
                    result, steps, log = self.run_sequence([{"properties": properties, "delay": 0.1}])
                    self.assertEqual(steps, [])
                    self.assertEqual(result["propertiesGeneration"], 0)
                    self.assertIn("phase=media-sequence-rejected", log)
        for entries in [[], [{"clear": True, "delay": 0.1}] * 9,
                        *[[{"clear": True, "delay": value}] for value in [0.099, 60.001, -1, "0.1", True]],
                        [{"path": "x" * 4097, "delay": 0.1}],
                        [{"path": "bad\n.png", "delay": 0.1}]]:
            with self.subTest(entries=str(entries)[:60]):
                _, steps, log = self.run_sequence(entries)
                self.assertEqual(steps, [])
                self.assertIn("phase=media-sequence-rejected", log)
        for raw in ["not json", "{}", "null", "[null]", '[{"clear":true}]',
                    '[{"clear":true,"delay":0.1},7]', '[{"clear":true,"delay":1e309}]',
                    '[{"timeline":{"position":1e309,"duration":1},"delay":0.1}]',
                    '[{"clear":true,"delay":0.1}]' + " " * (2 * 1024 * 1024)]:
            with self.subTest(raw=raw[:70]):
                _, steps, log = self.run_sequence(None, raw=raw)
                self.assertEqual(steps, [])
                self.assertIn("phase=media-sequence-rejected", log)

    def test_valid_boundary_properties_and_max_delay_are_admitted(self):
        result, steps, _ = self.run_sequence([
            {"properties": {"title": "x" * 4096, "artist": ""}, "delay": 0.1},
            {"clear": True, "delay": 60},
        ])
        self.assertEqual(result["properties"]["title"], "x" * 4096)
        self.assertEqual([s["index"] for s in steps], [0])

    def test_resource_failure_is_logged_false_and_preserves_inbox(self):
        for path in ["missing.png", "empty.png", "unsupported.txt", "../outside.png", "/tmp/absolute.png"]:
            with self.subTest(path=path):
                result, steps, log = self.run_sequence([
                    {"path": path, "delay": 0.1},
                    {"playbackState": 2, "delay": 0.1},
                ], seed=True)
                self.assertEqual([s["accepted"] for s in steps], [False, True])
                self.assertIn("phase=media-thumbnail-rejected", log)
                self.assertEqual(result["artGeneration"], 1)
                self.assertEqual(result["playbackState"], 2)


if __name__ == "__main__":
    unittest.main()
